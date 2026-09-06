# Playbooks

Step-by-step procedures for the recurring kinds of work in this repository.
`CLAUDE.md` holds the invariants; this file holds the how.

---

## Adding a rule

1. **Decide the scope before writing code, and write the boundary down.** Most
   of the cost in this project has been false positives, not missed findings.
   For anything touching step syntax, work out up front what must *not* fire:
   inline XML, JSON payloads, comments, table rows, scenario titles,
   free-text descriptions.

2. **Add fixtures first**, one that must fire and one that must not. Put the
   tricky cases in the negative fixture — that is the one that earns its keep.
   Whitespace-sensitive fixtures are generated with `printf` so tabs and
   trailing spaces are exact; `.gitattributes` marks `tests/fixtures/**` as
   `-text` so git never rewrites them.

3. **Write the rule** in `autoload/karate/linter.vim`. Statement-level rules
   take `docstring_body` and skip it. Anchor diagnostics with byte columns.

4. **Register the options** in `DEFAULTS` in `plugin/karate_linter.vim`
   (`_rule` and `_level`) and gate the rule with `RuleOn()` / `RuleLevel()`.

5. **Run `tests/run.sh`**, read the diff, confirm every new line is intended
   and no existing line moved. Then `--accept`.

6. **Add a toggle test** to the `option handling` section of `tests/run.sh`:
   one case asserting the finding count with the rule on, one with
   `--cmd 'let g:karate_linter_<name>_rule = 0'` asserting zero.

7. Document it in `README.md`, including the boundary from step 1.

---

## Changing an existing rule

The baseline diff is the review. Work so that it is small and readable:

- Make the behaviour change on its own, with no refactoring mixed in, so the
  diff shows only what the user will notice.
- If the change *removes* findings, satisfy yourself they were false positives
  and say so in the commit message. Removing a true positive is the one
  failure mode the suite cannot catch for you.
- Check whether other tests depended on the old behaviour. Widening the
  line-length rule to display columns removed a finding that the cursor-message
  test was relying on for its `(+N more)` assertion; the fixture had to be
  lengthened rather than the assertion weakened.

---

## Performance work

1. **Profile first.**
   ```vim
   profile start /tmp/profile.txt
   profile! file */karate_linter.vim
   ```
   then `sed -n '/FUNCTIONS SORTED ON TOTAL TIME/,/^$/p' /tmp/profile.txt`.

2. **Benchmark on a realistic file, not a synthetic one.** A generated file
   with no quotes made the delimiter scanner look free; on a file with quotes
   in every step it cost 788 ms. `/tmp/klbench/real.feature` in the session
   history was 60 scenarios of quoted URLs, JSON headers and `karate.get()`
   calls — that shape is what matters.

3. **Compare against a real "before".** Extract it from git:
   ```sh
   git show <ref>:plugin/karate_linter.vim > /tmp/before/plugin/karate_linter.vim
   ```
   **Never `git stash` inside a benchmark script.** A timeout mid-script leaves
   the working tree stashed; it happened once here.

4. **Re-measure after.** Two changes in this repo's history were reverted
   because the measurement did not support them:
   - short-circuiting the docstring lookups with `!empty()`: 0.5%, reverted;
   - moving the engine to `autoload/` for startup: within noise (35.9 vs
     36.2 ms), kept for architecture but the claim was corrected.

   And one was kept because it was large: a sound C-level pre-check in front of
   the character scanner, 953 → 202 ms.

5. **A cheap pre-check must not lose findings.** Comparing bracket *counts* is
   cheaper than collapsing pairs but silently misses `a) + read(` and `} + {`,
   where the counts match. Both are fixtures now.

---

## Releasing

1. `tests/run.sh` green, working tree clean.
2. Smoke-test a fresh install: a vimrc with nothing but
   `set runtimepath^=<repo>`, open a `.feature`, check the commands exist and
   that diagnostics, signs and the cursor message all appear.
3. Merge with `--no-ff`, tag annotated (`git tag -a vX.Y.Z`), push branch and
   tag separately.
4. A breaking change means a major version. Bumping the minimum Vim version
   counts, and so does adding rules that are on by default — existing files
   will light up. Both belong in the README's *Upgrading* section.

---

## Debugging the test harness

The traps below all cost time at least once in this project.

- **`vim -es` hangs forever** on a script error or a missing file: ex mode
  waits for input on stdin. Always `</dev/null`, and `timeout 90` for anything
  long. Two backgrounded 120-second timeouts here were both this.
- **See the error** with
  `vim -Nu NONE -es --cmd 'set verbosefile=/tmp/err.txt' -S script.vim`.
- **The shell's working directory persists between tool calls.** A `cd
  tests/fixtures` earlier in a command makes a later `vim -S tests/dump_report.vim`
  fail — and then hang, per the point above. Use paths from the repository root.
- **Setting a `g:` option before the plugin loads** needs `--cmd`, because the
  plugin has a load guard: `vim -Nu NONE -es --cmd 'let g:x = 0' -S t.vim`.
- **Capturing `echo` output** from an autocommand:
  `execute('doautocmd CursorMoved')` returns it.
- **Timers do fire under `-es`** during `sleep 400m`, so the debounce path is
  testable end to end.
- **Reaching script-local functions from a test is not needed.** Drive
  everything through the real autocommands (`doautocmd BufWinEnter`,
  `TextChanged`, `BufWritePre`) — it tests the event wiring at the same time,
  and it is why no `<SID>` hook survives in the plugin.

---

## Probing Vim behaviour

Assumptions about Vim have been wrong often enough here that probing is
cheaper than reasoning. Things that turned out not to be as expected:

| Assumed | Actually |
|---|---|
| `\b` is a word boundary | It is not, in Vim regex. The `callread` rule matched nothing for its whole life. |
| `printf('%.10S')` truncates to 10 cells | Truncates to 10 bytes; cut Cyrillic in half. |
| `match(str, pat, start)` respects `\<` | It treats `start` as the beginning of the string, so `\<foo\>` matched inside `xfoo`. |
| `str[i]` is a byte in Vim9 | It is a character. Use `strpart(str, i, 1)`. |
| `matchstrlist()` returns one match per line | It returns all of them, with `idx` and `byteidx`. |
| `prop_add_list()` end column | Exclusive, equal to `col + length` — verified against `prop_add()` before relying on it. |
| A quickfix item's `filename` always jumps | It is resolved against the current directory, so for an unnamed buffer the entry is still `valid: 1` but jumping does nothing at all. Use `bufnr`. |

The pattern for a probe: write a small script that prints results with
`writefile()`, run it with `vim -Nu NONE -es -S`, read the file.

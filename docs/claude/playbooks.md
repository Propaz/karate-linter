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

## Changing the formatter

The formatter is three steps in `AutoFormatOnSave()`: `FixupPass()`, a lint,
then `ApplyIndent()`. `:KarateFormat` is the same three with messages.

1. **Indent levels live in one place**, `ComputeLevels()`, which returns one
   level per line. `ApplyIndent()` only turns levels into leading whitespace.
   A new keyword is a line in `ComputeLevels()`, nothing else.

2. **Fixtures come in pairs here too**: one misindented file that must be
   rebuilt (fixture 32, asserted line by line) and correctly formatted files
   that must come back *untouched and unmodified* (the idempotence section).
   The second kind is what catches a formatter that "works" by rewriting
   everything.

3. **Assert the payload.** `s:Payload()` in `check_format.vim` dedents every
   docstring body by its opening delimiter, which is the string Karate
   actually receives. It must be identical before and after. This is the one
   assertion that would have caught the delimiter/body split that shipped in
   2.0.0.

4. **Check `&modified`.** A formatter that touches a file it should have left
   alone shows up here before it shows up anywhere else.

5. **Anything that adds or removes lines needs more than this.** The indent
   pass is line-preserving, which is why it can write with `setline()` and why
   diagnostics only need their columns refreshed afterwards. A pass that
   changes the line count has to deal with the ranges collected before it.

6. **Probe the ends of the file.** Both bugs found in the review of the first
   version were there: a tag or comment with nothing after it inherited from a
   `next_level` seeded with 0 and was pulled out to column 0, and an
   unrecognised fence was only caught in the middle of a file by accident. The
   fixtures all have well-formed middles.

7. **If the structure is uncertain, do nothing — including the fixups.** The
   error gate and `ForeignFence()` both sit in front of the whole formatter for
   the same reason: when the docstring boundaries are unknown, `ExpandTabs()`
   and `StripTrailingWhitespace()` corrupt a payload just as surely as
   `ApplyIndent()` would. Adding a fourth pass means deciding where in that
   order it goes, and the answer is almost always "after the gate".

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

   The ones that were kept were kept because the measurement was large, and
   each was measured in isolation before the work started:
   - dropping the `awk` subprocess per keystroke for an in-process scan, plus
     debouncing: 127 → 33 ms on a 220-line file, diagnostics identical;
   - a sound C-level pre-check in front of the character scanner, 953 → 202 ms;
   - the Vim9 port: 7.4× on an isolated loop, prototyped and measured *before*
     1540 lines were rewritten.

5. **A cheap pre-check must not lose findings.** Comparing bracket *counts* is
   cheaper than collapsing pairs but silently misses `a) + read(` and `} + {`,
   where the counts match. Both are fixtures now.

6. **Prove the old and new paths agree before deleting the old one.** The
   `awk` path was not removed until its output had been shown identical to the
   Vim fallback's on all 30 fixtures. That snapshot suite came first and became
   `tests/baseline.sorted.txt`; every optimisation since has been reviewed as a
   diff against it rather than by reasoning about the change.

---

## Releasing

1. `tests/run.sh` green, working tree clean.
2. Smoke-test a fresh install: a vimrc with nothing but
   `set runtimepath^=<repo>`, open a `.feature`, check the commands exist and
   that diagnostics, signs and the cursor message all appear. Then re-source
   the vimrc in that same Vim and use the plugin again — an *installed*
   plugin is sourced by a manager that may source it twice, and that path
   broke for three releases without any of the fresh-install checks noticing.
   Beware wrong expectations in the probe itself: `&filetype` on a `.feature`
   file is `cucumber` (the plugin hooks the file pattern, not the filetype),
   and the cursor message is prefixed `[karate]`, lowercase.

   **Prove a regression test fails against the old code.** Extract the
   previous version into a scratch tree and run the new test file there:

   ```sh
   mkdir -p /tmp/klold && cp -r autoload plugin tests /tmp/klold/
   git show HEAD:plugin/karate_linter.vim > /tmp/klold/plugin/karate_linter.vim
   (cd /tmp/klold && vim -Nu NONE -es -S tests/check_reload.vim </dev/null)
   ```

   A green test that would also have been green before the fix is worth
   nothing, and it is not obvious from reading it.
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
- **Auto-format on save refuses while the buffer has errors**, so a fixture
  for it has to be clean. That gate is why the whole docstring-restore path
  went untested through 2.0.0: the only tests that reached `BufWritePre` used
  dirty fixtures and so only ever exercised the refusal.
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
| `execute 'N,Mdelete _'` runs | `E1050: Colon required before a range` in Vim9. Same for `%s`. `deletebufline()` sidesteps it. |
| `sort(list, 'n')` sorts numeric strings | Only sorts real numbers. On `['114', '24']` it is a no-op and returns the input order. |
| `gg=G` reindents a `.feature` file | With no `'indentexpr'` and no `'equalprg'` — a Vim with no gherkin indent plugin — `=` falls back to the internal C indenter and flattens the file to column 0. Under `'noexpandtab'` it indents with tabs. |
| `doautocmd BufWritePre` fires `*.feature` autocommands | The pattern is matched against the buffer's **name**, so nothing fires in an unnamed buffer. A probe of the formatter did nothing at all and looked like "the formatter left it alone". `:file /tmp/x.feature` first. |
| Gherkin dedents a docstring body by the delimiter's column | Only as far as the line allows — the dedent clamps. A body indented *less* than its own delimiter arrives flattened onto column 0, so the nesting on screen is not in the string. `:KarateAlignDocstring` exists for exactly that. |
| Searching outwards from the cursor finds the docstring it is in | With the cursor *between* two blocks, a backwards search finds a closing delimiter and a forwards search an opening one, and the two bracket the cursor just like a real block. Pair the delimiters from the top instead — `DocstringBlockAt()`. |
| The engine recognises every Gherkin docstring fence | `DOCSTRING_PATTERN` is `^\s*"""\s*$`. `"""json` produces a false *Unclosed DocString*; `'''` is not seen at all, lints clean, and used to have its body reindented as though it were steps. |
| Sourcing the plugin twice is harmless | A Vim9 script's script-local items — vars, imports, `def`s — are cleared before a re-source, and a load guard then `finish`es before they can come back. Autocommands from the first load outlive it and hit `E121`. `vim9script noclear`, invariant 10. |
| `:colorscheme` wipes the plugin's highlight groups | `highlight default link` is re-established by the `:highlight clear` a colorscheme runs, so the links survive. Probed against four colorschemes before deciding not to add a `ColorScheme` autocommand. |
| `&modified == 0` proves the formatter wrote nothing | Only for a buffer loaded from disk. A buffer built with `setline()` in a test is already modified before the formatter runs, so the assertion fails whatever the code does. Compare `b:changedtick` across the save instead — it asserts the stronger thing. |

**A probe whose input already looks like the expected answer proves nothing.**
`sort(['24', '42', '114'], 'n')` came back in the same order and was read as
success; the list had been sorted to begin with. The same mistake produced a
green location-list test that jumped to the line the cursor was already on.
Give a probe an input that can only survive if the code works.

The same rule applies to assertions, and it is worth more there. The first
version of `check_format.vim` asserted that lines outside the docstrings had
*changed* — which was green precisely because the formatter was flattening
every one of them to column 0. **Assert the value, not that something moved.**
Where an exact value is genuinely unknown, an assertion that a *correctly
formatted* input comes back untouched catches the same class of bug: four such
fixtures now sit in the idempotence section, and all four failed against the
old engine.

A gate is the other shape of this trap. A test for "the formatter refuses on a
broken file" must use an input the formatter *would* visibly change — the
refusal check used a line that was already at the right indentation, so it
passed whether the gate held or not.

The pattern for a probe: write a small script that prints results with
`writefile()`, run it with `vim -Nu NONE -es -S`, read the file.

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

   The cases run through `tests/check_options.vim`, one Vim per case because of
   the plugin's load guard, driven by three environment variables: `KL_RESULT`
   (the file the `"<count> <level>"` line is written to), `KL_FIXTURE`
   (default `14_parens_bad.feature`) and `KL_MATCH` (default `Unclosed '('`),
   the pattern that selects which diagnostics are counted. `opt_case` **unsets
   `KL_FIXTURE` and `KL_MATCH` after every case**, so a pair that needs them
   has to export them twice — which is what the repeated `export` lines in
   that section are, not a copy-paste slip.

   **Do not read that section as a measure of the suite's coverage.** The
   convention was applied to the rules added after it and never backwards: 7
   of the 22 `_rule` options have a toggle case, and the other 15 — the
   `missing_*` family, `unused_variable`, `unclosed_docstring`,
   `undefined_placeholder`, `unused_header` and the rest — have none, so for
   those the `_rule = 0` path has never been executed at all. Nine of them
   also rest on `12_clean.feature` alone for their negative half, which means
   a false positive shows up only as a baseline line and never as a named
   failure.

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

7. **A save-time pass may not edit a payload — the fixups included.** This is
   the class boundary in invariant 4, and it is easy to cross here because a
   fixup looks too small to count: expanding a tab is one `substitute()`, and
   it shipped for three releases rewriting docstring payload on every save.
   Before adding or widening a pass, ask what it does to a *delimiter* line
   too, not only to a body line. Anything that must edit a payload belongs in
   the explicit, cursor-driven class instead, and `ExpandTabs()` shows the
   shape: one implementation, and the caller supplies the policy.

8. **If the structure is uncertain, do nothing — including the fixups.** The
   error gate and `ForeignFence()` both sit in front of the whole formatter for
   the same reason: when the docstring boundaries are unknown, `ExpandTabs()`
   and `StripTrailingWhitespace()` corrupt a payload just as surely as
   `ApplyIndent()` would. Adding a fourth pass means deciding where in that
   order it goes, and the answer is almost always "after the gate".

---

## Performance work

1. **Profile first**, and profile the *engine*:
   ```vim
   profile start /tmp/profile.txt
   profile! file */karate/linter.vim
   ```
   then `sed -n '/FUNCTIONS SORTED ON TOTAL TIME/,/^$/p' /tmp/profile.txt`.

   The pattern matters. `*/karate_linter.vim` matches only
   `plugin/karate_linter.vim`, which is 154 lines of options, commands and
   autocommands with no hot code in it — it profiles cleanly and tells you
   nothing. Everything worth measuring is in `autoload/karate/linter.vim`.

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
   Vim fallback's on every fixture that existed then — 30 of them; there are
   more now. That snapshot suite came first and became
   `tests/baseline.sorted.txt`; every optimisation since has been reviewed as a
   diff against it rather than by reasoning about the change.

---

## Releasing

1. `tests/run.sh` green, working tree clean.
2. The fresh-install smoke test is `tests/check_install.vim`, and `run.sh`
   already ran it: a vimrc containing nothing but `set runtimepath^=<repo>`,
   so Vim loads the plugin itself rather than an explicit `:source`, then the
   commands, the diagnostics, the signs and the cursor message, then a second
   source of the plugin file — what a manager's update hook does, and the path
   that broke for three releases without any fresh-install check noticing.
   Dropping `vim9script noclear` fails two of its assertions with `E121`.

   What it cannot do is look at the screen. Once per release, open a real
   `.feature` in an interactive Vim and check that the highlights, the gutter
   and the message look right — every rendering bug in this project's history
   was found that way and none of them by an assertion.
   Beware wrong expectations in the probe itself. The cursor message is
   prefixed `[karate]`, lowercase. And `&filetype` is a trap twice over: with
   filetype detection on it is `cucumber`, not `karate` — but the smoke
   probe's own vimrc contains nothing but the `runtimepath` line, so detection
   is *off* there and `&filetype` is empty. Asserting `cucumber` fails against
   a perfectly working plugin. What the probe should assert is that
   diagnostics appear anyway: the plugin hooks the file *pattern*, so it works
   with detection off, and that is worth pinning rather than the filetype.

   **Prove a regression test fails against the old code.** Build a scratch
   tree at the ref *before* the fix, drop the new test into it, and run it
   there:

   ```sh
   rm -rf /tmp/klold && mkdir -p /tmp/klold
   git archive <before> | tar -x -C /tmp/klold   # tracked files only
   cp tests/check_reload.vim /tmp/klold/tests/   # new test, old engine
   (cd /tmp/klold && rm -f tests/reload.txt \
     && timeout 90 vim -Nu NONE -es -S tests/check_reload.vim </dev/null)
   grep 'RESULT:' /tmp/klold/tests/reload.txt
   ```

   A green test that would also have been green before the fix is worth
   nothing, and it is not obvious from reading it. Two ways this check lies,
   both of which have happened:

   - **`<before>` is not `HEAD` once the fix is committed.** `HEAD` then
     already contains the fix, and the test passes for the honest reason. Use
     the commit before it, or the merge-base of the branch.
   - **A stale result file reads as success.** Each `check_*.vim` writes its
     verdict to a gitignored `tests/<name>.txt`, and a script that dies on
     startup writes nothing at all — so whatever is already at that path is
     what you read. `cp -r tests` copies one in; `git archive` cannot, since
     the file is untracked, and the `rm -f` makes a missing file distinguish
     itself from a passing one. Assert on the printed `RESULT:` line, not on
     the exit status.
3. Merge with `--no-ff`, tag annotated (`git tag -a vX.Y.Z`), push branch and
   tag separately.
4. A breaking change means a major version. Bumping the minimum Vim version
   counts, and so does adding rules that are on by default — existing files
   will light up. Both belong in the README's *Upgrading* section.

---

## Debugging the test harness

`tests/run.sh` is the report snapshot plus seven scripts. It takes no filter
flag, so to run one, run it directly — and to run the whole suite against
another build, `VIM=` selects the binary, which is the only way to check the
9.1.0009 floor:

```sh
vim -Nu NONE -es -S tests/check_echo.vim </dev/null
VIM=/opt/vim91/bin/vim tests/run.sh
```

`check_install.vim` is the exception to that first command: it needs the
minimal vimrc `run.sh` writes for it, because being loaded by Vim itself is
the thing it tests.

```sh
printf 'set runtimepath^=%s\n' "$PWD" > /tmp/klvimrc
vim -Nu /tmp/klvimrc -es -S tests/check_install.vim </dev/null
```

| Script | What it holds down |
|---|---|
| `check_diagnostics.vim` | the report → text-props/signs pipeline, byte columns, sign identity |
| `check_echo.vim` | the cursor-line message, its `(+N more)` suffix, the debounce timer |
| `check_loclist.vim` | `:KarateLintCheck`, the location list, and that jumping works |
| `check_format.vim` | the formatter: payload preservation, the refusal gate, idempotence |
| `check_options.vim` | one option scenario per invocation — see *Adding a rule*, step 6 |
| `check_reload.vim` | surviving a re-source; the `noclear` invariant |
| `check_install.vim` | the fresh-install path: Vim's own plugin loading, then a second source |
| `check_conventions.vim` | the project's rules about itself — see *Auditing a claim* |

Each writes its verdict to a gitignored `tests/<name>.txt`, and the pass
contract is the literal line `RESULT: ALL OK`, which `run.sh` greps for. So
the suite reports failure *by absence*: a script that dies on startup writes
nothing, and `run.sh` says only that the string was missing. Read the script's
own output file to find out what actually broke — and see *Releasing* for how
a leftover file from a previous run turns this into a false pass.

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
| `:colorscheme` wipes the plugin's highlight groups | `highlight default link` is re-established by the `:highlight clear` a colorscheme runs, so the links survive — probed before deciding not to add a `ColorScheme` autocommand. `check_reload.vim:76` keeps one such probe (`colorscheme default`). |
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

---

## When a hypothesis needs an adversarial pass

The suite reviews a diff; nothing reviews an idea. Three kinds of idea here
have cost more than the code that implemented them, and for those it is worth
having something actively try to break the proposal *before* it is written.
For everything else the baseline diff is the review, and a second opinion is
noise — most changes in this repository are small and the contract catches
them.

1. **Widening a shared boundary.** `DOCSTRING_PATTERN` is the engine's whole
   idea of where a docstring is, so widening it moves every docstring rule at
   once — which is why invariant 4 asks for its own change and its own
   baseline. The same shape: `STEP_PATTERN`, the `docstring_body` map, the
   level table in `ComputeLevels()`. The question to answer first is not "is
   the new pattern right" but "which rules change answer if it lands".

2. **Touching a payload, or wanting to run on save.** The line between the
   two classes of formatter command *is* the payload, and a save-time pass
   that edits one is the most damaging thing this plugin can do: Karate
   receives a different string and no diagnostic ever fires. Such a proposal
   always arrives looking like a tidy save-time fix — see invariant 4 for
   where it belongs instead.

3. **A rule's boundary.** Most of the cost in this project has been false
   positives, so what must *not* fire is the decision, and it is worth
   arguing before there is code to defend. *Adding a rule*, step 1.

An optimisation argued instead of measured is a fourth, but it already has a
cheaper answer than debate: *Performance work*, step 1.

---

## Auditing a claim, or a document, against the code

Four classes of decay are now checked on every run by
`tests/check_conventions.vim` — an undocumented option, a rule whose off
switch is never executed, a document naming a function or file that no longer
exists, and a fixture the baseline has never seen. Start an audit by reading
that script, so it covers what is left rather than what is already automated.

For the rest, the discipline is the same one the probe table is built on:

- **A claim counts as checked only when a command ran and its output was
  read.** Every finding this repository's audits have produced came from
  checking a claim against something that can say no — a grep, a `git log
  -S`, a patched scratch tree — and none came from reasoning about whether a
  claim sounded right.
- **Three verdicts, and the third is a real answer.** Confirmed, refuted, or
  unverifiable. "Probed against four colorschemes" and the performance
  numbers are unverifiable from the repository, and saying so is worth more
  than a confident guess in either direction.
- **Cite `file:line`.** A claim without one cannot be rechecked next year,
  and the conventions gate now keeps such citations honest.
- **Check the checker.** A check that is supposed to fail must be *shown*
  failing, against a deliberately broken copy of the tree — every assertion
  in `check_conventions.vim` was, and fixture 34 was too. And make the
  breakage announce itself: two of those mutation cases first came back green
  because the mutation had silently failed to apply, not because the check
  worked. That is the trap at the top of this section wearing different
  clothes.

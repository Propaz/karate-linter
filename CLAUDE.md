# karate-linter.vim — working notes

A Vim plugin that lints Karate `.feature` files. Requires Vim 9.1.0009+.

Detailed procedures live in `docs/claude/playbooks.md` (adding a rule, changing
one, performance work, releasing, debugging the harness). Read that file before
starting any of those; this one is only the things that cause real damage when
forgotten.

## Layout

| Path | What it is |
|---|---|
| `plugin/karate_linter.vim` | Thin. Options, highlight links, commands, autocommands. Vim9 script. |
| `autoload/karate/linter.vim` | The engine. Reached via `import autoload`, so it is not compiled until a `.feature` buffer exists. |
| `tests/` | The suite. `tests/baseline.sorted.txt` is committed and is the contract. |

## The contract

`tests/baseline.sorted.txt` records every diagnostic the linter emits over the
fixtures. **Any diff there is a change in what the linter reports.**

```sh
tests/run.sh            # compare against the baseline
tests/run.sh --accept   # re-record it
```

**Only `baseline.sorted.txt` is a gate.** A diff in `baseline.raw.txt` prints
as a `note` and does *not* fail the suite — it records the order the report is
built in, which is the order the location list puts the user through. Read
that note; nothing else will make you.

The two commands are not symmetric. `--accept` runs `dump_report.vim` alone,
so it re-records the baseline without running any of the six `check_*.vim`
scripts — it can leave a red suite looking accepted. Run the suite again
afterwards.

Never run `--accept` to make a red suite green. Read every line of the diff
first and be able to say why each one moved. Most of the real bugs in this
project's history were found exactly this way — as an unexplained baseline
line, not as a crash.

The suite must be green before any commit.

## The user's own `.feature` files are off limits

Real files the user shares to reproduce a bug are **not** test material. They
must not be committed, must not be split up into fixtures, and must not be
used as a regression input — they carry internal hostnames, customer names and
directory layouts. Put them in `tests/local/` (gitignored, and outside the
`tests/fixtures/*.feature` glob the baseline is built from) and never stage
them.

Reproduce the bug in a fixture written from scratch instead: take the
*structural* shape that triggered it — "several docstrings in a row", "a table
after a comment" — and rebuild it with invented content.

## Invariants that are easy to break

1. **Columns are byte offsets.** `prop_add()` wants bytes. In Vim9 script
   `str[i]` indexes by *character*, so the scanners use `strpart(str, i, 1)`.
   Fixture 30 asserts that the reported column, sliced out of the line by
   bytes, is exactly the expected text.

2. **Never build a regular expression out of text taken from the file.**
   Placeholder names and Examples headers are user text and may contain
   metacharacters. Use `stridx()`, or positions produced by `ParseTableRow()`.
   Interpolating a name into a pattern once produced a column of 0 and an
   `E964` out of `prop_add()` that killed the render for the whole buffer.

3. **Docstring bodies are payload, not Karate syntax.** Statement-level rules
   skip them (`docstring_body`, built once in the main loop). But *usages*
   still count there: Karate evaluates `#(expr)` inside docstrings and Gherkin
   substitutes `<placeholder>` into them, so skipping a whole line in the
   unused-variable or unused-header rules invents false positives. Only
   *definitions* are skipped.

4. **The formatter must not change a docstring's payload.** Gherkin strips the
   indentation of the opening `"""` from every body line, so the body has to
   move by exactly the amount the delimiter moved — or the string Karate sends
   changes. `ApplyIndent()` shifts the body textually, one space at a time, so
   it never rewrites a tab and never touches a blank line. `check_format.vim`
   asserts the dedented payload directly; that assertion, and nothing else,
   is what pins this down.

   The corollary: **`DOCSTRING_PATTERN` is the whole engine's idea of where a
   docstring is, and it only matches a bare `"""` alone on its line.** Gherkin
   also allows `"""json` and `'''`, and for those the engine's block
   boundaries are simply wrong — `'''` linted clean and the indent pass then
   moved the delimiter without its body. `ForeignFence()` therefore switches
   the *entire* formatter off for such a file, fixup pass included: with the
   boundaries unknown, stripping a trailing space is as damaging as
   reindenting. Widening `DOCSTRING_PATTERN` instead would move every
   docstring rule at once, so it needs its own change and its own baseline.

   **Two classes of command, and the line between them is the payload.**
   `AutoFormatOnSave()` and `FormatBuffer()` must leave it byte-identical.
   `FormatJsonInDocstring()` and `AlignDocstringBody()` rewrite it on purpose,
   so they are explicit, per-block and cursor-driven, and **must never be
   wired into an autocommand**. Anything that edits a payload belongs in the
   second class, however tempting it looks as a save-time fix.

   Note also that Gherkin's dedent *clamps*: it cannot remove more whitespace
   than a line has, so a body indented less than its own delimiter arrives
   flattened. `s:Payload()` in `check_format.vim` models that; without the
   clamp it sliced into the content of such a line and the assertion was
   comparing nonsense.

5. **Never echo from `UpdateDiagnostics()`.** It runs from the buffer-load and
   buffer-write autocommands, where the cursor is not placed yet and Vim is
   about to print its own message; a second one forces a `Press ENTER` prompt.
   `OnLintTimer()` is the only safe place to refresh the message.

6. **`=~` still honours `'ignorecase'` in Vim9.** Comparison operators do not,
   but pattern matching does. Any pattern matching a Gherkin keyword needs
   `\C`. Legacy patterns without it were left as they were — do not assume a
   rule is case-sensitive, check.

7. **Close `echohl`.** Every `echohl X` needs a matching `echohl NONE`, or the
   highlight leaks into every later message in the session.

8. **Dictionary keys are strings in Vim9.** The docstring map and the per-line
   diagnostic index key on `string(lnum)` explicitly. Two consequences bit at
   once in the formatting code: `sort(keys(d), 'n')` does **not** sort — the
   `'n'` flag is a no-op on a list of strings, and it returns the dictionary's
   own order looking like it worked. Iterate a list in file order instead.

9. **A range inside `:execute` needs a leading colon.** Vim9 rejects
   `execute '5,9delete _'` with `E1050`; it has to be `execute ':5,9…'`, `%s`
   included. Prefer `deletebufline()` and friends, which take no range at all.
   `silent!` in front of such a command hides the error and leaves the command
   silently doing nothing — that shipped in 2.0.0 and made
   `:KarateTabsToSpaces` a no-op that still reported success.

10. **`plugin/karate_linter.vim` must stay `vim9script noclear`.** A guarded
    Vim9 script needs it. Re-sourcing one — `:source $MYVIMRC`, a plugin
    manager's update hook — clears its script-local items *before* executing,
    and the `exists('g:loaded_karate_linter')` guard then `finish`es before
    the `import autoload` can be re-created. The autocommands and commands
    from the first load survive that and still resolve against the emptied
    script, so every one of them dies with `E121: Undefined variable: linter`
    until Vim is restarted — on `CursorMoved`, which is to say on every
    keystroke. `KarateLinterReport()` kept working and hid how broad it was:
    it is a compiled `def g:` whose reference resolved at compile time.
    `tests/check_reload.vim` covers it, and 12 of its assertions fail if the
    `noclear` is dropped.

    The highlight links next to it need no such care: `highlight default link`
    is restored by the `:highlight clear` inside `:colorscheme`, so they
    survive a colorscheme change and the plugin wants no `ColorScheme`
    autocommand. That was worth probing — the expectation was the opposite.

## Conventions

- **Measure before optimising, and measure again after.** This repository's
  history contains an "obvious" optimisation that turned out to be worth 0.5%
  and was reverted, and others worth several times over. Guessing was wrong
  both ways. The numbers are in `docs/claude/playbooks.md`; keep them in that
  one place rather than restating them here, where they go stale unnoticed.
- **A behaviour change must be visible in the baseline diff** and explained in
  the commit message.
- **A new rule needs fixtures for both answers** — one that must fire and one
  that must not — plus a test that its `_rule` toggle switches it off.
- Options are `g:karate_linter_<name>_rule` / `_level`. Renaming one means
  keeping the old name working as an alias.
- Commit messages explain *why*, including measurements and anything that was
  tried and rejected.

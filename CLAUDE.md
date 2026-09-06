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
| `tests/` | The suite. `tests/baseline.*.txt` is committed and is the contract. |

## The contract

`tests/baseline.sorted.txt` records every diagnostic the linter emits over the
fixtures. **Any diff there is a change in what the linter reports.**

```sh
tests/run.sh            # compare against the baseline
tests/run.sh --accept   # re-record it
```

Never run `--accept` to make a red suite green. Read every line of the diff
first and be able to say why each one moved. Most of the real bugs in this
project's history were found exactly this way — as an unexplained baseline
line, not as a crash.

The suite must be green before any commit.

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

4. **Never echo from `UpdateDiagnostics()`.** It runs from the buffer-load and
   buffer-write autocommands, where the cursor is not placed yet and Vim is
   about to print its own message; a second one forces a `Press ENTER` prompt.
   `OnLintTimer()` is the only safe place to refresh the message.

5. **`=~` still honours `'ignorecase'` in Vim9.** Comparison operators do not,
   but pattern matching does. Any pattern matching a Gherkin keyword needs
   `\C`. Legacy patterns without it were left as they were — do not assume a
   rule is case-sensitive, check.

6. **Close `echohl`.** Every `echohl X` needs a matching `echohl NONE`, or the
   highlight leaks into every later message in the session.

7. **Dictionary keys are strings in Vim9.** The docstring map and the per-line
   diagnostic index key on `string(lnum)` explicitly.

## Conventions

- **Measure before optimising, and measure again after.** This repository's
  history contains an "obvious" optimisation that turned out to be worth 0.5%
  and was reverted, and another worth 21×. Guessing was wrong both times.
- **A behaviour change must be visible in the baseline diff** and explained in
  the commit message.
- **A new rule needs fixtures for both answers** — one that must fire and one
  that must not — plus a test that its `_rule` toggle switches it off.
- Options are `g:karate_linter_<name>_rule` / `_level`. Renaming one means
  keeping the old name working as an alias.
- Commit messages explain *why*, including measurements and anything that was
  tried and rejected.

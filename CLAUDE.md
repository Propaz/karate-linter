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
| `docs/claude/playbooks.md` | The procedures. Read it before adding or changing a rule, touching the formatter, optimising, releasing, or debugging the harness. |

`.gitignore` ignores `*.feature` everywhere and makes exactly one exception,
`!tests/fixtures/*.feature` — not `**`. So a fixture belongs *directly* in
that directory: one placed in a subdirectory is silently untrackable, and the
baseline glob would not see it either. Any other `.feature` file in the tree,
including a scratch one in the repository root, is invisible to git by design
— that is the mechanism behind `tests/local/`.

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

They are named rather than numbered, and referred to by name everywhere. The
numbering drifted once already — a renumbering left a reference pointing at the
wrong rule — and `tests/check_conventions.vim` now fails on a reference that
names nothing.

### Columns are byte offsets

`prop_add()` wants bytes. In Vim9 script `str[i]` indexes by *character*, so
the scanners use `strpart(str, i, 1)`. Fixture 30 asserts that the reported
column, sliced out of the line by bytes, is exactly the expected text.

Three measures of "column" live here, each correct about a different thing.
Mixing them up is the likeliest way to land a diagnostic in the wrong place,
or nowhere:

| Measure | Where | Unit |
|---|---|---|
| `col` / `end_col` of a diagnostic | every rule, `prop_add_list()` | 1-based **bytes** |
| the `max_line_length` threshold | `ColumnBeyondWidth()` | **display cells** |
| clipping the cursor message | `TruncateToWidth()` | **display cells** |

`ColumnBeyondWidth()` is where they meet: it takes a limit in cells and
returns the *byte* offset of the character past it, so a rule can compare
widths and still anchor in bytes. Both descriptions are true of that one
number, which is why the pair reads like a contradiction until you look.

### Never build a pattern out of file text

Placeholder names and Examples headers are user text and may contain
metacharacters. Use `stridx()`, or positions produced by `ParseTableRow()`.
Interpolating a name into a pattern once produced a column of 0 and an `E964`
out of `prop_add()` that killed the render for the whole buffer.

### A diagnostic is one fixed record

The shape is `{lnum, col, end_col, text, level}`: `col` a 1-based *byte*
offset, `end_col` exclusive and equal to `col + length`, `level` one of the
two highlight group names. Every rule, every test and the baseline format
depend on it, and the only place it is written down is the comment above
`KarateLinterReport()` in `plugin/`.

A malformed record is discarded in silence. `UpdateDiagnostics()` skips any
record with `col < 1` or `end_col <= col` before rendering — on purpose, so
that one bad column cannot abort the render for a whole buffer the way the
`E964` in *Never build a pattern out of file text* did. But the record still
comes back from `GenerateReport()`, so it still reaches the report and the
baseline: **the suite can be green while nothing at all is highlighted.** A
new rule wants a look at a real buffer, not only a baseline line.

### Docstring bodies are payload

The body of a `"""` block is not Karate syntax. Statement-level rules skip it
(`docstring_body`, built once in the main loop). But *usages* still count
there: Karate evaluates `#(expr)` inside docstrings and Gherkin substitutes
`<placeholder>` into them, so skipping a whole line in the unused-variable or
unused-header rules invents false positives. Only *definitions* are skipped.
Fixture 34 is the half of that which has no other cover.

### The formatter must not change a payload

Gherkin strips the indentation of the opening `"""` from every body line, so
the body has to move by exactly the amount the delimiter moved — or the string
Karate sends changes. `ApplyIndent()` shifts the body textually, one space at
a time, so it never rewrites a tab and never touches a blank line.
`check_format.vim` asserts the dedented payload directly; that assertion, and
nothing else, is what pins this down.

Gherkin's dedent *clamps*: it cannot remove more whitespace than a line has,
so a body indented less than its own delimiter arrives flattened.
`s:Payload()` in `check_format.vim` models that; without the clamp it sliced
into the content of such a line and the assertion was comparing nonsense.

### The engine knows only one docstring fence

`DOCSTRING_PATTERN` is the whole engine's idea of where a docstring is, and it
only matches a bare `"""` alone on its line. Gherkin also allows `"""json` and
the three-apostrophe fence, and for those the engine's block boundaries are
simply wrong — the apostrophe form linted clean and the indent pass then moved
the delimiter without its body. `ForeignFence()` therefore switches the
*entire* formatter off for such a file, fixup pass included: with the
boundaries unknown, stripping a trailing space is as damaging as reindenting.
Widening `DOCSTRING_PATTERN` instead would move every docstring rule at once,
so it needs its own change and its own baseline.

### Two classes of command

The line between them is the payload. `AutoFormatOnSave()` and
`FormatBuffer()` must leave it byte-identical — and "the payload" is wider than
the body lines. A tab on a *delimiter* line changes the indentation Gherkin
strips from every body line, so expanding it rewrites the string Karate
receives without touching a body line at all. That is why the save-time tab
fix skips whole docstring blocks, delimiters included, while the
trailing-space fix only needs to skip the bodies; `DocstringMaps()` returns
both answers for that reason.

`FormatJsonInDocstring()` and `AlignDocstringBody()` rewrite the payload on
purpose, so they are explicit, per-block and cursor-driven, and **must never
be wired into an autocommand**. Anything that edits a payload belongs in that
second class, however tempting it looks as a save-time fix. `ExpandTabs()`
shows how to serve both: one implementation, and the caller supplies the
policy.

### Never echo from UpdateDiagnostics

It runs from the buffer-load and buffer-write autocommands, where the cursor
is not placed yet and Vim is about to print its own message; a second one
forces a `Press ENTER` prompt. `OnLintTimer()` is the only safe place to
refresh the message.

### The b: state belongs to UpdateDiagnostics

`GenerateReport()` is pure; the autocommand-driven function is what sets
`b:karate_has_errors` (the gate the formatter refuses on),
`b:karate_diagnostics` (the per-line index, keyed `string(lnum)`),
`b:karate_echoed` and `b:karate_just_formatted_json`. A test that calls
`KarateLinterReport()` and then reads any of them reads a stale value or none
at all; fire `doautocmd BufWinEnter` first. Every existing test does, and none
of them says why.

### Sign and property identity is derived

The two property types (`karate_lint_error`, `karate_lint_warn`) and the two
sign definitions are created once at engine load and are *global*, not
buffer-local — hence the `prop_type_get()` guard around each. Per buffer, the
sign group is `karate_linter_<bufnr>` and a sign's id is `SIGN_ID_BASE + lnum`,
so one line can only ever hold one sign and re-linting replaces rather than
accumulates. A second sign per line has nowhere to go without changing that
scheme, and `check_diagnostics.vim` asserts both the one-sign-per-line count
and that an error outranks a warning in the gutter.

### RuleOn defaults to off

It is `get(g:, '…_rule', 0)`, so a rule whose options were never added to
`DEFAULTS` is silently dead — no error at any layer, no findings, and a
baseline that looks like the rule simply had nothing to say. `RuleLevel()`
defaults to `Error` instead, which means a half-registered rule can also come
back at the wrong level. Registering the options is step 4 of the playbook for
exactly this reason.

`max_line_length` is the one deliberate exception to the `_rule`/`_level`
pair: it is a numeric option with a `_level` and no `_rule`.

### The plugin defines no mappings

`<CR>` in the location list is Vim's own built-in jump; claiming it — with a
mapping or a `FileType qf` autocommand — would break the thing the README's
troubleshooting section explains how to unbreak, since a user's `<C-m>`
mapping already collides with it. Signs, text properties, commands and
autocommands are the whole surface. Adding a mapping needs a reason and an
option to turn it off, not a convenience.

### The plugin file must stay noclear

`plugin/karate_linter.vim` begins `vim9script noclear`, and a guarded Vim9
script needs it. Re-sourcing one — `:source $MYVIMRC`, a plugin manager's
update hook — clears its script-local items *before* executing, and the
`exists('g:loaded_karate_linter')` guard then `finish`es before the `import
autoload` can be re-created. The autocommands and commands from the first load
survive that and still resolve against the emptied script, so every one of
them dies with `E121: Undefined variable: linter` until Vim is restarted — on
`CursorMoved`, which is to say on every keystroke. `KarateLinterReport()` kept
working and hid how broad it was: it is a compiled `def g:` whose reference
resolved at compile time. `tests/check_reload.vim` covers it, and 12 of its
assertions fail if the `noclear` is dropped; `tests/check_install.vim` fails
two more, through Vim's own plugin loading.

### Pattern matching honours ignorecase

`=~` still respects `'ignorecase'` in Vim9. Comparison operators do not, but
pattern matching does. Any pattern matching a Gherkin keyword needs `\C`.
Legacy patterns without it were left as they were — do not assume a rule is
case-sensitive, check.

### Dictionary keys are strings

The docstring map and the per-line diagnostic index key on `string(lnum)`
explicitly. Two consequences bit at once in the formatting code:
`sort(keys(d), 'n')` does **not** sort — the `'n'` flag is a no-op on a list of
strings, and it returns the dictionary's own order looking like it worked.
Iterate a list in file order instead.

### A range inside execute needs a colon

Vim9 rejects `execute '5,9delete _'` with `E1050`; it has to be
`execute ':5,9…'`, `%s` included. Prefer `deletebufline()` and friends, which
take no range at all. `silent!` in front of such a command hides the error and
leaves the command silently doing nothing — that shipped in 2.0.0 and made
`:KarateTabsToSpaces` a no-op that still reported success.

### Close every echohl

Every `echohl X` needs a matching `echohl NONE`, or the highlight leaks into
every later message in the session.

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

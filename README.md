# karate-linter.vim

A simple, fast, and modern linter for [Karate](https://github.com/karatelabs/karate) API testing framework `.feature` files.

This plugin provides real-time linting for common errors and style issues in Karate feature files directly within Vim/Neovim.

## Features

-   **Modern Real-time Diagnostics:** Uses Vim's built-in `textprop` and `signs` for stable, non-intrusive feedback as you type. Errors and warnings are marked with gutter icons (`>>` and `W>`) and highlighted directly in your code.
-   **Comprehensive Rules:** Checks for syntax errors, style conventions, and logical problems.
-   **Finds Unused Variables:** Warns about variables defined with `* def` that are never used in the file.
-   **Scenario Outline Validation:** Checks for undefined placeholders in steps and unused parameter definitions in `Examples` tables.
-   **Request Variable Validation:** Ensures variables used in a `request` step are defined beforehand.
-   **High Performance:** Vim9 script, no subprocesses. Linting is debounced
    while you type, so a burst of keystrokes costs one pass rather than one per
    key, and the engine is loaded lazily - nothing is read or compiled until
    you open your first `.feature` file.
-   **Gherkin-aware Formatting:** Indents the file on save from the Gherkin
    structure itself — not through `=`, which knows nothing about `.feature`
    files. Docstring blocks (`"""..."""`) move as a unit, so embedded JSON,
    JavaScript and expected payloads come out byte for byte identical. See
    [Formatting](#formatting).
-   **JSON Formatting:** Includes a command to format JSON content within a docstring block on demand.
-   **Configurable:** Most rules and their severity levels can be easily customized.

## Upgrading to 2.2

-   **Auto-format on save no longer uses `gg=G`.** It computes Gherkin
    indentation itself, so the result is the same with or without a gherkin
    indent plugin installed. If you were relying on `=` and your own
    `indentexpr`, set `g:karate_linter_auto_format_on_save = 0` and keep
    formatting with `=` by hand.
-   **Saving now fixes tabs and trailing whitespace** instead of refusing to
    format because of them. Both are Error-level rules, and any error stopped
    the formatter, so these were the two things it could have fixed and never
    did. Turning the respective rule off also turns its fix off.
-   **Indentation is always spaces**, `g:karate_linter_indent_width` of them
    per level (default 4). `'expandtab'`, `'shiftwidth'` and `'tabstop'` do not
    affect it — the previous behaviour indented with tabs under `'noexpandtab'`
    and then reported every line it had touched as an error.

## Upgrading from 1.x

-   **Vim 9.1.0009 or newer is now required.** The engine is Vim9 script; on an
    older Vim the plugin prints a message and does nothing rather than failing
    obscurely.
-   **The plugin now ships an `autoload/` directory** alongside `plugin/`. Any
    plugin manager handles this; if you vendored `plugin/karate_linter.vim` by
    hand, copy the whole repository instead.
-   **Expect new findings on files that were previously clean.** Unbalanced
    brackets, unterminated strings, Examples-table consistency, duplicate
    `Feature:`/`Background:`/scenario names and stray `<placeholder>`s are all
    on by default, and the `callread` rule now actually fires — it never
    matched anything before. Each has its own `_rule` toggle.
-   **`g:karate_linter_unclosed_read_rule` / `_level` still work.** They are
    applied to the rule that replaced them,
    `g:karate_linter_unbalanced_parens_*`.
-   **`g:karate_linter_max_line_length` now counts display columns, not
    bytes.** Non-ASCII lines that used to be flagged at roughly half the stated
    limit no longer are.

## Installation

Install using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'Propaz/karate-linter'
```

Requires Vim 9.1.0009 or newer.

The plugin is split in two: `plugin/karate_linter.vim` only declares options,
commands and autocommands, while the engine lives in
`autoload/karate/linter.vim` and is pulled in through `import autoload` on
first use.

Then run `:PlugInstall` in Vim.

## Usage

The linter runs automatically as you type. When an issue is detected, the line will be highlighted, and a sign will appear in the gutter (the column with line numbers).
-   `>>` for errors
-   `W>` for warnings

A line with more than one finding gets a single sign, and an error outranks a
warning there.

The message for the line under the cursor is shown in the command line; see [Seeing the message](#seeing-the-message).

## Commands

The plugin provides several commands that you can run manually:

-   `:KarateLintCheck`
    -   Runs the linter on the entire file and opens the results in a location list, for reviewing every issue in one place — and for jumping between them.

    The list is ordered the way the file reads, top to bottom, and each entry
    points at the buffer it came from:

    | | |
    |---|---|
    | `<CR>` | jump to the entry under the cursor |
    | `:lnext` / `:lprevious` | next / previous issue, without leaving the file |
    | `:lfirst` / `:llast` | first / last issue |
    | `:lclose` | close the list |

    The list opens with the first issue at or after your cursor already
    selected, so `<CR>` goes where you were looking. Re-running the command
    rebuilds the list; if nothing is left to report it closes the window rather
    than leaving entries that no longer match the file.

-   `:KarateFormat`
    -   Formats the buffer now: expands tabs, strips trailing whitespace and
        reindents from the Gherkin structure. Same work the save does, on
        demand — useful when auto-format on save is off, or on a file you have
        just pasted in. It refuses to reindent a file that still has errors and
        says so; see [Formatting](#formatting).

-   `:KarateFmtJson`
    -   Formats the JSON content within a docstring (`"""..."""`) block. The cursor must be inside the block you wish to format. It uses `jq` or `python -m json.tool` if available.

-   `:KarateAlignDocstring`
    -   Re-anchors the docstring block under the cursor so its least-indented
        line lines up with the opening `"""`. Use it on a body that hangs to
        the *left* of its own delimiter, where Karate is receiving something
        other than what you see; see
        [Docstring bodies that hang left](#docstring-bodies-that-hang-left).
        Like `:KarateFmtJson` it edits the payload, so it is never run for you.

-   `:KarateTabsToSpaces`
    -   Replaces all tab characters in the file with spaces, according to your `shiftwidth` setting.

## Configuration

You can customize the linter by adding `let g:variable_name = value` to your `vimrc` or `init.vim`.

### General
-   `g:karate_linter_auto_format_on_save`: Format the file on save. Tabs and
    trailing whitespace are fixed first; reindenting is skipped if any errors
    remain after that. See [Formatting](#formatting).
    -   Default: `1` (enabled)
-   `g:karate_linter_indent_width`: Spaces per indent level.
    -   Default: `4`

### Rules and Levels
For each rule, you can enable/disable it (`_rule`) and set its severity level (`_level`).
Severity can be `KarateLintError` (uses `Error` highlight group) or `KarateLintWarn` (uses `Todo` highlight group).

-   **Max line length:** measured in display columns — what you actually see,
    with tabs expanded.
    -   `g:karate_linter_max_line_length`: maximum columns per line. Set to `0`
        to disable.
    -   `g:karate_linter_max_line_length_level`: Severity.
    -   Defaults: `120`, `'KarateLintWarn'`
    -   This used to count bytes, which halved the effective limit for
        non-ASCII text: a Cyrillic step 83 columns wide was reported as 143.
        The highlight starts at the first character past the limit, on a
        character boundary.

-   **Tabs:** Disallow tab characters.
    -   `g:karate_linter_tabs_rule`: `1` or `0`.
    -   `g:karate_linter_tabs_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Trailing whitespace:**
    -   `g:karate_linter_trailing_space_rule`: `1` or `0`.
    -   `g:karate_linter_trailing_space_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Use `And` instead of `But`:**
    -   `g:karate_linter_and_but_rule`: `1` or `0`.
    -   `g:karate_linter_and_but_level`: Severity.
    -   Defaults: `1`, `'KarateLintWarn'`

-   **Space after Gherkin keyword:** (`Given`, `When`, etc.)
    -   `g:karate_linter_no_space_after_keyword_rule`: `1` or `0`.
    -   `g:karate_linter_no_space_after_keyword_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **`Scenario Outline` without `Examples`:**
    -   `g:karate_linter_missing_examples_rule`: `1` or `0`.
    -   `g:karate_linter_missing_examples_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **`Examples` without `Scenario Outline`:**
    -   `g:karate_linter_orphaned_examples_rule`: `1` or `0`.
    -   `g:karate_linter_orphaned_examples_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **`callread` instead of `call read`:**
    -   `g:karate_linter_call_read_space_rule`: `1` or `0`.
    -   `g:karate_linter_call_read_space_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Unused variable:** (`* def myVar = ...`)
    -   `g:karate_linter_unused_variable_rule`: `1` or `0`.
    -   `g:karate_linter_unused_variable_level`: Severity.
    -   Defaults: `1`, `'KarateLintWarn'`

-   **Unbalanced bracket in a step:** covers `(`, `{` and `[` — any function
    call (`read(...)`, `call read(...)`, any `karate.*(...)`, your own JS
    helpers) as well as inline JSON and array literals, including nested cases
    such as `read(foo(bar)` and `{ a: [1, 2 }`.
    -   `g:karate_linter_unbalanced_parens_rule`: `1` or `0`.
    -   `g:karate_linter_unbalanced_parens_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`
    -   Only step lines are inspected (`*`, `Given`, `When`, `Then`, `And`,
        `But`). Brackets inside string literals (`'`, `"`, `` ` ``, with
        backslash escapes) are ignored, as is a trailing `//` comment — but
        not the `//` in a URL. Docstring bodies are skipped entirely, and when
        a docstring is left unclosed the rest of the file is skipped too, so
        that the docstring rule reports it alone. A bare grouping paren
        (`* def x = (a + b`) is out of scope; for `(` the check is about calls.
        Braces and brackets need no such test — in Karate they are always data
        literals.
    -   Replaces the former `read()`-only rule. Setting the old
        `g:karate_linter_unclosed_read_rule` / `_level` still works and is
        applied to this rule, so existing configuration keeps working.

### Seeing the message

Signs in the gutter (`>>` for errors, `W>` for warnings) and the inline
highlight show *that* a line has a problem. The message itself is echoed in the
command line for whichever line the cursor is on:

```
[karate] E: Unclosed '(' in call to 'karate.jsonPath'
```

-   `g:karate_linter_echo_cursor`: `1` or `0`. Default `1`.

Details worth knowing:

-   When a line carries several diagnostics, the one under the cursor column
    wins; otherwise errors are preferred over warnings, and the rest are
    summarised as `(+N more)`.
-   Long messages are clipped to the width of the command line so that Vim
    never stops with a `Press ENTER` prompt. Clipping counts display cells, so
    non-ASCII names survive intact.
-   The command line is only written to when the message actually changes, to
    avoid wiping messages from other plugins on every cursor movement.
-   Normal and visual mode only — echoing during insert would fight with the
    completion menu.
-   Nothing is printed while a file is being opened or written. Vim prints its
    own message at those moments, and a second one on top of it would force a
    `Press ENTER` prompt. When an edit changes the diagnostic on the line the
    cursor is already on — which produces no cursor movement — the message is
    refreshed once the debounce timer has run.

`:KarateLintCheck` still opens the full list in the location list, where
`<CR>` and `:lnext` jump between the findings.

### Docstrings and rule scope

The body of a `"""` block is payload — JSON, JS, XML, GraphQL — not Karate
syntax. Rules that parse Karate statements therefore stop at the block
delimiters: unbalanced parentheses, `callread`, `But`/`And`, missing space
after a keyword, unused variables, undefined `request` variables, and every
structural rule (`Feature:` / `Scenario:` / `Background:` / `Examples:`
detection). Without this a JSON payload that merely mentions `Examples:`, or a
line of JS starting with `*`, produced phantom errors.

Two deliberate exceptions:

-   **Tabs are still reported inside docstrings** — they break indentation
    wherever they appear. Trailing whitespace and maximum line length are not,
    since both are normal in a payload.
-   **Variable and placeholder *usages* still count inside docstrings.** Karate
    evaluates embedded expressions such as `#(userId)`, and Gherkin substitutes
    `<placeholder>` values into docstrings, so a variable used only inside a
    block is genuinely used and is not reported as unused. Only *definitions*
    (`* def x = ...`) are ignored there.

The `"""` delimiter lines themselves are treated as Karate syntax, so trailing
whitespace on them is still flagged.

-   **Unterminated string literal in a step:** `Given path 'oops`
    -   `g:karate_linter_unterminated_string_rule`: `1` or `0`.
    -   `g:karate_linter_unterminated_string_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`
    -   Reported on its own: an unterminated quote swallows the rest of the
        line, so bracket findings after it would just bury the real cause.

-   **Examples table consistency:** a data row whose cell count disagrees with
    the header, a duplicated column name, a header with no data rows under it,
    and an `Examples:` block with no table at all.
    -   `g:karate_linter_examples_table_rule`: `1` or `0`.
    -   `g:karate_linter_examples_table_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Duplicate `Feature:` block:** a feature file declares exactly one.
    -   `g:karate_linter_duplicate_feature_rule`, `..._level`
    -   Defaults: `1`, `'KarateLintError'`

-   **`Background:` in the wrong place:** repeated, or placed after the first
    `Scenario:` (invalid Gherkin — a Background applies to the scenarios that
    follow it).
    -   `g:karate_linter_background_placement_rule`, `..._level`
    -   Defaults: `1`, `'KarateLintError'`

-   **Duplicate scenario name:** ambiguous in reports and in `--name` filters.
    -   `g:karate_linter_duplicate_scenario_name_rule`, `..._level`
    -   Defaults: `1`, `'KarateLintWarn'`

-   **`<placeholder>` in a plain `Scenario`:** nothing substitutes it there, so
    it is almost always a step copied out of a `Scenario Outline`.
    -   `g:karate_linter_placeholder_outside_outline_rule`, `..._level`
    -   Defaults: `1`, `'KarateLintWarn'`
    -   Only identifier-shaped names count, and a line containing `</` or `/>`
        is skipped: Karate allows inline XML such as
        `* def body = <root>text</root>`, whose tags are not placeholders.

-   **Unclosed docstring (`"""`):**
    -   `g:karate_linter_unclosed_docstring_rule`: `1` or `0`.
    -   `g:karate_linter_unclosed_docstring_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`
    
-   **Undefined placeholder in `Scenario Outline`:**
    -   `g:karate_linter_undefined_placeholder_rule`: `1` or `0`.
    -   `g:karate_linter_undefined_placeholder_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Unused header in `Examples` table:**
    -   `g:karate_linter_unused_header_rule`: `1` or `0`.
    -   `g:karate_linter_unused_header_level`: Severity.
    -   Defaults: `1`, `'KarateLintWarn'`

-   **Undefined variable in `request`:**
    -   `g:karate_linter_undefined_request_var_rule`: `1` or `0`.
    -   `g:karate_linter_undefined_request_var_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Missing `Feature` block:**
    -   `g:karate_linter_missing_feature_rule`: `1` or `0`.
    -   `g:karate_linter_missing_feature_level`: Severity.
    -   Defaults: `1`, `'KarateLintWarn'`

-   **Missing `Scenario` block:**
    -   `g:karate_linter_missing_scenario_rule`: `1` or `0`.
    -   `g:karate_linter_missing_scenario_level`: Severity.
    -   Defaults: `1`, `'KarateLintWarn'`

-   **Missing `Background` block:**
    -   `g:karate_linter_missing_background_rule`: `1` or `0`.
    -   `g:karate_linter_missing_background_level`: Severity.
    -   Defaults: `1`, `'KarateLintWarn'`

---

## Formatting

Both `:KarateFormat` and the save-time formatter do the same three things, in
this order.

**1. Fix what can be fixed.** Tabs become spaces and trailing whitespace is
removed. Only for rules that are switched on: turning `tabs_rule` off tells the
plugin that tabs are acceptable in this project, so it stops converting them.
Trailing whitespace *inside* a docstring is left alone — the rule does not
report it there, because it is part of the string being sent.

**2. Lint, and stop here if errors remain.** Reindenting a file whose structure
the linter cannot make sense of is how payloads get corrupted: with an unclosed
`"""` the block boundaries are wrong, and a payload line would be indented as
though it were a step. `:KarateFormat` tells you it refused; a save is silent,
and the gutter shows why.

The same caution applies to a docstring fence this plugin does not recognize.
It understands a bare `"""` alone on its line, which is the form Karate's own
documentation uses. Gherkin also allows a content type after the fence
(`"""json`) and `'''` as an alternative; if either appears, the plugin does not
know where the docstrings are and so does **nothing at all** to the file —
step 1 included, since even stripping a trailing space could take a byte out of
a payload. `:KarateFormat` names the line.

**3. Reindent.** From the structure, in units of
`g:karate_linter_indent_width` (default 4):

| Level | Lines |
|---|---|
| 0 | `Feature:` |
| 1 | `Background:`, `Scenario:`, `Scenario Outline:`, and the free-text description under `Feature:` |
| 2 | steps (`Given`, `When`, `Then`, `And`, `*`), `Examples:`, the `"""` delimiters |
| 3 | table rows (`\| a \| b \|`) |

A tag or a comment takes the level of whatever follows it, so `@smoke` lines up
with its `Scenario:` and a comment lines up with the step it explains. When
there is nothing after it — a note under the last step, a block of
commented-out scenarios at the end of the file — it keeps the level of what it
follows instead. Blank lines are emptied of whitespace. Anything else is
treated as free text at the level of its surroundings.

Indentation is always spaces. `'expandtab'`, `'shiftwidth'` and `'tabstop'` are
not consulted — the width above is in spaces by definition.

**Docstring bodies are payload.** Gherkin strips the indentation of the opening
`"""` from every line of the body, so the body is shifted by exactly the amount
its delimiter moved and its internal shape is preserved. The string Karate
receives is unchanged, byte for byte. Nothing else inside a block is touched:
not a line that looks like a step, not a line that looks like a table row.

A file that is already formatted is not rewritten — not one line, and the
buffer is not marked modified. Formatting twice changes nothing the second
time.

### Docstring bodies that hang left

Gherkin dedents each body line by the column of the opening `"""` — but it can
only remove whitespace that is there. A body indented *less* than its own
delimiter is therefore clamped, and the structure you see is not the structure
Karate gets:

```
        """
    for (var i = 0; i < 3; i++) {     ← 4 spaces, delimiter is at 8
      if (i > 1) {
        total = total + i;
      }
    }
        """
```

Every one of those lines arrives at column 0, flat. It runs fine — the nesting
was only ever cosmetic — but if you were counting on the indentation reaching
Karate, it never did.

`:KarateAlignDocstring`, with the cursor in the block, shifts the whole body
right until its least-indented line meets the delimiter. The internal shape is
preserved exactly, and the payload then carries the nesting you can see.

This is deliberately **not** part of formatting. Realigning changes the string
Karate receives, and the formatter's guarantee is that it does not — so the
command is explicit and per-block, on the same terms as `:KarateFmtJson`. For
the same reason it only ever shifts a block *right*: indentation beyond the
delimiter's column is preserved by Gherkin, which makes it real payload, and
pulling an over-indented block left would quietly rewrite a YAML or
plain-text docstring. A body indented with tabs is refused rather than guessed
at — run `:KarateTabsToSpaces` first.

What the formatter does **not** do: it never reflows or wraps, so a step over
`g:karate_linter_max_line_length` stays too long (and a line pushed over the
limit by its new indentation will start being reported). It never reorders
anything, and it never changes a line's contents beyond its leading whitespace
and any tab in it.

## Customizing Highlights and Signs

The linter uses standard Vim highlight groups for errors and warnings:
-   `KarateLintError` links to the `Error` highlight group.
-   `KarateLintWarn` links to the `Todo` highlight group.

The signs use these same highlight groups for their colors. You can customize these in your `vimrc` to match your preferred color scheme. For example:

```vim
" Customize error highlights
highlight Error ctermfg=white ctermbg=red guifg=white guibg=red

" Customize warning highlights
highlight Todo ctermfg=black ctermbg=yellow guifg=black guibg=yellow
```

You can also change the signs themselves:
```vim
sign define KarateLintError text=E!
sign define KarateLintWarn text=W!
```

---

## Troubleshooting

### `<CR>` in the location list does nothing

Almost always a mapping of your own, and the usual culprit is `<C-m>`.

Vim sends the same byte for Ctrl-M and Enter — carriage return, decimal 13 —
and in a terminal it cannot tell them apart. A normal-mode mapping for `<C-m>`
is therefore a mapping for `<CR>` *everywhere*, including the location list,
where Enter is the built-in jump rather than a mapping that could override it.

Check with:

```vim
:nmap <CR>
```

If that prints anything, it is what Enter does in the list. The same collision
exists for `<C-i>`/`<Tab>`, `<C-[>`/`<Esc>` and `<C-h>`/`<BS>`.

Either move the mapping off Enter, or give the list window its own:

```vim
autocmd FileType qf nnoremap <buffer> <CR> <CR>
```

A buffer-local mapping wins over a global one, and `nnoremap` is non-recursive,
so this runs the built-in jump rather than looping back into your mapping.

`:lnext` and `:lprevious` are unaffected either way, and need no mapping to
walk the list.

---

## Contributing

Contributions are welcome! If you find a bug, have a feature request, or want to contribute code, please feel free to:

1.  **Open an issue**: Report bugs or suggest new features on the [GitHub Issues page](https://github.com/Propaz/karate_linter/issues).
2.  **Submit a pull request**: If you've implemented a fix or a new feature, please open a pull request. Ensure your code adheres to the existing style and conventions.

---

## License

This project is licensed under the MIT License - see the LICENSE.md file for details.

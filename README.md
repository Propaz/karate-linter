# karate-linter.vim

A simple, fast, and modern linter for [Karate](https://github.com/karatelabs/karate) API testing framework `.feature` files.

This plugin provides real-time linting for common errors and style issues in Karate feature files directly within Vim/Neovim.

## Features

-   **Modern Real-time Diagnostics:** Uses Vim's built-in `textprop` and `signs` for stable, non-intrusive feedback as you type. Errors and warnings are marked with gutter icons (`>>` and `W>`) and highlighted directly in your code.
-   **Comprehensive Rules:** Checks for syntax errors, style conventions, and logical problems.
-   **Finds Unused Variables:** Warns about variables defined with `* def` that are never used in the file.
-   **Scenario Outline Validation:** Checks for undefined placeholders in steps and unused parameter definitions in `Examples` tables.
-   **Request Variable Validation:** Ensures variables used in a `request` step are defined beforehand.
-   **High Performance:** Pure Vimscript, no subprocesses. Linting is debounced while you type, so a burst of keystrokes costs one pass, not one per key.
-   **Smart Auto-formatting:** Optionally formats the file on save (`gg=G`), intelligently preserving the content of docstring blocks (`"""..."""`) to avoid corrupting embedded JSON or other data.
-   **JSON Formatting:** Includes a command to format JSON content within a docstring block on demand.
-   **Configurable:** Most rules and their severity levels can be easily customized.

## Installation

Install using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'Propaz/karate-linter'
```

Requires Vim 9.1.0009 or newer.

Then run `:PlugInstall` in Vim.

## Usage

The linter runs automatically as you type. When an issue is detected, the line will be highlighted, and a sign will appear in the gutter (the column with line numbers).
-   `>>` for errors
-   `W>` for warnings

The message for the line under the cursor is shown in the command line; see [Seeing the message](#seeing-the-message).

## Commands

The plugin provides several commands that you can run manually:

-   `:KarateLintCheck`
    -   Runs the linter on the entire file and displays the results in a location list (`:lopen`). This is useful for reviewing all issues in one place.

-   `:KarateFmtJson`
    -   Formats the JSON content within a docstring (`"""..."""`) block. The cursor must be inside the block you wish to format. It uses `jq` or `python -m json.tool` if available.

-   `:KarateTabsToSpaces`
    -   Replaces all tab characters in the file with spaces, according to your `shiftwidth` setting.

## Configuration

You can customize the linter by adding `let g:variable_name = value` to your `vimrc` or `init.vim`.

### General
-   `g:karate_linter_auto_format_on_save`: Enable auto-formatting on save. This will not run if any errors are detected.
    -   Default: `1` (enabled)

### Rules and Levels
For each rule, you can enable/disable it (`_rule`) and set its severity level (`_level`).
Severity can be `KarateLintError` (uses `Error` highlight group) or `KarateLintWarn` (uses `Todo` highlight group).

-   **Max line length:**
    -   `g:karate_linter_max_line_length`: Max characters per line. Set to `0` to disable. Note: this check is byte-based for maximum compatibility.
    -   `g:karate_linter_max_line_length_level`: Severity.
    -   Defaults: `120`, `'KarateLintWarn'`

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

`:KarateLintCheck` still opens the full list in the location list.

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

## Contributing

Contributions are welcome! If you find a bug, have a feature request, or want to contribute code, please feel free to:

1.  **Open an issue**: Report bugs or suggest new features on the [GitHub Issues page](https://github.com/Propaz/karate_linter/issues).
2.  **Submit a pull request**: If you've implemented a fix or a new feature, please open a pull request. Ensure your code adheres to the existing style and conventions.

---

## License

This project is licensed under the MIT License - see the LICENSE.md file for details.

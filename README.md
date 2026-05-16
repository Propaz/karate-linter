# karate-linter.vim

A simple, fast, and modern linter for [Karate](https://github.com/karatelabs/karate) API testing framework `.feature` files.

This plugin provides real-time linting for common errors and style issues in Karate feature files directly within Vim/Neovim.

## Features

-   **Modern Real-time Diagnostics:** Uses Vim's built-in `textprop` and `signs` for stable, non-intrusive feedback as you type. Errors and warnings are marked with gutter icons (`>>` and `W>`) and highlighted directly in your code.
-   **Comprehensive Rules:** Checks for syntax errors, style conventions, and logical problems.
-   **Finds Unused Variables:** Warns about variables defined with `* def` that are never used in the file.
-   **High Performance:** Uses `ripgrep` and `awk` for fast, whole-file analysis when available, with a seamless fallback to pure Vimscript otherwise.
-   **Auto-formatting:** Optionally formats the file on save (`gg=G`), if no errors are detected.
-   **Configurable:** Most rules and their severity levels can be easily customized.

## Installation

Install using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
" Make sure you have ripgrep and awk for the best performance
Plug 'Propaz/karate-linter'
```

Then run `:PlugInstall` in Vim.

## Configuration

You can customize the linter by adding `let g:variable_name = value` to your `vimrc` or `init.vim`.

### General
-   `g:karate_linter_auto_format_on_save`: Enable auto-formatting on save.
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

-   **Unclosed `read()` function:**
    -   `g:karate_linter_unclosed_read_rule`: `1` or `0`.
    -   `g:karate_linter_unclosed_read_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Unclosed docstring (`"""`):**
    -   `g:karate_linter_unclosed_docstring_rule`: `1` or `0`.
    -   `g:karate_linter_unclosed_docstring_level`: Severity.
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

## Usage

When an issue is detected, the line will be highlighted, and a sign will appear in the gutter (the column with line numbers).
-   `>>` for errors
-   `W>` for warnings

You can also run `:KarateLintCheck` to get a full report in the location list (`:lopen`).

### Example

Consider a `.feature` file with a `Scenario Outline` missing an `Examples` block. The linter would highlight the problematic line and place an error icon (`>>`) in the gutter next to it.

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

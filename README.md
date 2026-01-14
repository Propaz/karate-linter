# karate-linter.vim

A simple linter for [Karate](https://github.com/karatelabs/karate) API testing framework `.feature` files.

This plugin provides real-time linting for common errors and style issues in Karate feature files directly within Vim/Neovim.

## Features

-   **Real-time feedback:** Highlights issues as you type.
-   **Comprehensive rules:** Checks for syntax errors, style conventions, and logical problems (like unclosed blocks).
-   **High performance:** Uses `ripgrep` and `awk` for fast, whole-file analysis when available, with seamless fallback to pure Vimscript otherwise.
-   **Auto-formatting:** Optionally formats the file on save (`gg=G`), if no errors are detected.
-   **Configurable:** Rules and severity levels can be easily customized.

## Installation

Install using [vim-plug](https://github.com/junegunn/vim-plug):

```vim
" Make sure you have ripgrep and awk for the best performance
Plug 'Propaz/karate_linter'
```

Then run `:PlugInstall` in Vim.

## Configuration

You can customize the linter by adding `let g:variable_name = value` to your `vimrc` or `init.vim`.

### General
-   `g:karate_linter_auto_format_on_save`: Enable auto-formatting on save.
    -   Default: `1` (enabled)

### Rules and Levels
For each rule, you can enable/disable it (`_rule`) and set its severity level (`_level`).
Severity can be `KarateLintError` (uses `Error` highlight group) or `Todo` (uses `Todo` highlight group).

-   **Max line length:**
    -   `g:karate_linter_max_line_length`: Max characters per line. Set to `0` to disable.
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

-   **Unclosed `read()` function:**
    -   `g:karate_linter_unclosed_read_rule`: `1` or `0`.
    -   `g:karate_linter_unclosed_read_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

-   **Unclosed docstring (`"""`):**
    -   `g:karate_linter_unclosed_docstring_rule`: `1` or `0`.
    -   `g:karate_linter_unclosed_docstring_level`: Severity.
    -   Defaults: `1`, `'KarateLintError'`

---

## Usage Example

Consider a `.feature` file named `example.feature` with the following content:

```gherkin
Feature: User Login

  Scenario Outline: Successful login with valid credentials
    Given a user with username <username> and password <password>
    When the user logs in
    Then the login should be successful
```

Here, the `Scenario Outline` is missing an `Examples` block. The `karate-linter.vim` plugin would highlight the line containing `"Scenario Outline: Successful login with valid credentials"` as an error (e.g., in red, depending on your Vim color scheme).

You can also run `:KarateLintCheck` to get a full report in the location list (`lopen`).

```
example.feature|4 col 3| Error: 'Scenario Outline' without a corresponding 'Examples' block
```

---

## Customizing Highlight Colors

The linter uses standard Vim highlight groups for errors and warnings:
-   `KarateLintError` links to the `Error` highlight group.
-   `KarateLintWarn` links to the `Todo` highlight group.

You can customize these in your `vimrc` or `init.vim` to match your preferred color scheme. For example:

```vim
" Customize error highlights (e.g., bright red background, white foreground)
highlight Error guifg=#FFFFFF guibg=#FF0000 ctermfg=white ctermbg=red

" Customize warning highlights (e.g., yellow background, black foreground)
highlight Todo guifg=#000000 guibg=#FFFF00 ctermfg=black ctermbg=yellow
```

Remember to choose colors that provide good contrast for readability.

---

## Contributing

Contributions are welcome! If you find a bug, have a feature request, or want to contribute code, please feel free to:

1.  **Open an issue**: Report bugs or suggest new features on the [GitHub Issues page](https://github.com/Propaz/karate_linter/issues).
2.  **Submit a pull request**: If you've implemented a fix or a new feature, please open a pull request. Ensure your code adheres to the existing style and conventions.

Your feedback and contributions help make this linter better for everyone.

---

## License

This project is licensed under the MIT License - see the LICENSE.md file for details.

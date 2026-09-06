vim9script
# karate-linter.vim - linting for Karate .feature files.
#
# This file stays deliberately small: it only declares configuration, the
# highlight groups, the commands and the autocommands. The engine lives in
# autoload/karate/linter.vim and is pulled in through `import autoload`, so it
# is neither read nor compiled until the first .feature file is opened.

if exists('g:loaded_karate_linter')
  finish
endif

# matchstrlist() (used by the unused-variable scan) landed in Vim 9.1.0009,
# and the engine is Vim9 script. Fail loudly here rather than throwing E117 on
# the first lint.
if !has('patch-9.1.9')
  echohl WarningMsg
  echomsg '[Karate] karate_linter.vim requires Vim 9.1.0009 or newer.'
  echohl NONE
  finish
endif

g:loaded_karate_linter = 1

import autoload 'karate/linter.vim' as linter


# --- Configuration -------------------------------------------------------

const DEFAULTS = {
  karate_linter_max_line_length: 120,
  karate_linter_max_line_length_level: 'KarateLintWarn',
  karate_linter_tabs_rule: 1,
  karate_linter_tabs_level: 'KarateLintError',
  karate_linter_trailing_space_rule: 1,
  karate_linter_trailing_space_level: 'KarateLintError',
  karate_linter_and_but_rule: 1,
  karate_linter_and_but_level: 'KarateLintWarn',
  karate_linter_no_space_after_keyword_rule: 1,
  karate_linter_no_space_after_keyword_level: 'KarateLintError',
  karate_linter_auto_format_on_save: 1,
  karate_linter_missing_examples_rule: 1,
  karate_linter_missing_examples_level: 'KarateLintError',
  karate_linter_call_read_space_rule: 1,
  karate_linter_call_read_space_level: 'KarateLintError',
  karate_linter_unbalanced_parens_rule: 1,
  karate_linter_unbalanced_parens_level: 'KarateLintError',
  karate_linter_unterminated_string_rule: 1,
  karate_linter_unterminated_string_level: 'KarateLintError',
  karate_linter_examples_table_rule: 1,
  karate_linter_examples_table_level: 'KarateLintError',
  karate_linter_duplicate_feature_rule: 1,
  karate_linter_duplicate_feature_level: 'KarateLintError',
  karate_linter_background_placement_rule: 1,
  karate_linter_background_placement_level: 'KarateLintError',
  karate_linter_duplicate_scenario_name_rule: 1,
  karate_linter_duplicate_scenario_name_level: 'KarateLintWarn',
  karate_linter_placeholder_outside_outline_rule: 1,
  karate_linter_placeholder_outside_outline_level: 'KarateLintWarn',
  karate_linter_orphaned_examples_rule: 1,
  karate_linter_orphaned_examples_level: 'KarateLintError',
  karate_linter_unclosed_docstring_rule: 1,
  karate_linter_unclosed_docstring_level: 'KarateLintError',
  karate_linter_missing_feature_rule: 1,
  karate_linter_missing_feature_level: 'KarateLintWarn',
  karate_linter_missing_scenario_rule: 1,
  karate_linter_missing_scenario_level: 'KarateLintWarn',
  karate_linter_missing_background_rule: 1,
  karate_linter_missing_background_level: 'KarateLintWarn',
  karate_linter_unused_variable_rule: 1,
  karate_linter_unused_variable_level: 'KarateLintWarn',
  karate_linter_undefined_placeholder_rule: 1,
  karate_linter_undefined_placeholder_level: 'KarateLintError',
  karate_linter_unused_header_rule: 1,
  karate_linter_unused_header_level: 'KarateLintWarn',
  karate_linter_undefined_request_var_rule: 1,
  karate_linter_undefined_request_var_level: 'KarateLintError',
  karate_linter_debounce_ms: 150,
  karate_linter_echo_cursor: 1,
}

# Back-compat: the unbalanced-bracket check grew out of the old read()-only
# rule and replaces it. An explicit setting of the old option is carried over
# so existing vimrcs keep working, and this has to run before the defaults
# below so the alias wins over the default value.
if exists('g:karate_linter_unclosed_read_rule')
    && !exists('g:karate_linter_unbalanced_parens_rule')
  g:karate_linter_unbalanced_parens_rule = g:karate_linter_unclosed_read_rule
endif
if exists('g:karate_linter_unclosed_read_level')
    && !exists('g:karate_linter_unbalanced_parens_level')
  g:karate_linter_unbalanced_parens_level = g:karate_linter_unclosed_read_level
endif

# 'keep' adds only the options the user has not set.
extend(g:, DEFAULTS, 'keep')


# --- Highlighting --------------------------------------------------------
# The text-property types and the signs are defined by the engine, on the
# first lint. These links are cheap and belong here so a colorscheme can be
# overridden from a vimrc without the engine having been loaded.

highlight default link KarateLintError Error
highlight default link KarateLintWarn Todo


# --- Commands ------------------------------------------------------------

# Public entry point for tests and debugging: the raw diagnostic list
# ({lnum, col, end_col, text, level}) for the current buffer.
def g:KarateLinterReport(): list<dict<any>>
  return linter.GenerateReport()
enddef

command! -bar KarateLintCheck linter.ShowLoclist()
command! -bar KarateFmtJson linter.FormatJsonInDocstring()
command! -bar KarateTabsToSpaces linter.ReplaceTabsWithSpaces()


# --- Autocommands --------------------------------------------------------

augroup KarateLinter
  autocmd!
  # Lint when the buffer becomes visible or is (re)loaded. Text properties and
  # signs are buffer-local and survive window switches, so there is no
  # BufLeave teardown followed by a full recompute on BufEnter.
  autocmd BufWinEnter,BufReadPost *.feature linter.UpdateDiagnostics()

  # Debounced re-lint while editing.
  autocmd TextChanged,TextChangedI *.feature linter.ScheduleUpdate()

  # Message for the line under the cursor. Normal and visual mode only:
  # echoing while inserting fights with the completion menu.
  autocmd CursorMoved *.feature linter.EchoDiagnostic()

  # Nothing pending should outlive the buffer.
  autocmd BufUnload *.feature linter.CancelPendingUpdate()

  autocmd BufWritePre *.feature linter.AutoFormatOnSave()
augroup END

" ~/.vim/plugin/karate_linter.vim

" Prevent plugin from being loaded multiple times
if exists("g:loaded_karate_linter")
  finish
endif
let g:loaded_karate_linter = 1


" --- CONFIGURATION ---
let s:defaults = {
    \ 'karate_linter_max_line_length': 120,
    \ 'karate_linter_max_line_length_level': 'KarateLintWarn',
    \ 'karate_linter_tabs_rule': 1,
    \ 'karate_linter_tabs_level': 'KarateLintError',
    \ 'karate_linter_trailing_space_rule': 1,
    \ 'karate_linter_trailing_space_level': 'KarateLintError',
    \ 'karate_linter_and_but_rule': 1,
    \ 'karate_linter_and_but_level': 'KarateLintWarn',
    \ 'karate_linter_no_space_after_keyword_rule': 1,
    \ 'karate_linter_no_space_after_keyword_level': 'KarateLintError',
    \ 'karate_linter_auto_format_on_save': 1,
    \ 'karate_linter_missing_examples_rule': 1,
    \ 'karate_linter_missing_examples_level': 'KarateLintError',
    \ 'karate_linter_call_read_space_rule': 1,
    \ 'karate_linter_call_read_space_level': 'KarateLintError',
    \ 'karate_linter_unclosed_read_rule': 1,
    \ 'karate_linter_unclosed_read_level': 'KarateLintError',
    \ 'karate_linter_orphaned_examples_rule': 1,
    \ 'karate_linter_orphaned_examples_level': 'KarateLintError',
    \ 'karate_linter_unclosed_docstring_rule': 1,
    \ 'karate_linter_unclosed_docstring_level': 'KarateLintError',
    \ 'karate_linter_missing_feature_rule': 1,
    \ 'karate_linter_missing_feature_level': 'KarateLintWarn',
    \ 'karate_linter_missing_scenario_rule': 1,
    \ 'karate_linter_missing_scenario_level': 'KarateLintWarn',
    \ 'karate_linter_missing_background_rule': 1,
    \ 'karate_linter_missing_background_level': 'KarateLintWarn'
    \ }

for var_name in keys(s:defaults)
    if !exists('g:' . var_name)
        let default_value = s:defaults[var_name]
        execute 'let g:' . var_name . ' = ' . string(default_value)
    endif
endfor
unlet s:defaults
" --- END CONFIGURATION ---


function! s:generate_lint_report()
    let report = []
    let filename = bufname('%')

    " --- Simple rules (line-by-line check) ---
    for lnum in range(1, line('$'))
        let line = getline(lnum)

        if g:karate_linter_tabs_rule && line =~ '\t'
            call add(report, {'filename': filename, 'lnum': lnum, 'text': 'Tabs are not allowed', 'type': g:karate_linter_tabs_level == 'KarateLintError' ? 'E' : 'W'})
        endif

        if g:karate_linter_trailing_space_rule && line =~ '\s\+$'
            call add(report, {'filename': filename, 'lnum': lnum, 'text': 'Trailing whitespace', 'type': g:karate_linter_trailing_space_level == 'KarateLintError' ? 'E' : 'W'})
        endif

        if g:karate_linter_max_line_length > 0 && len(line) > g:karate_linter_max_line_length
            call add(report, {'filename': filename, 'lnum': lnum, 'text': printf('Line is too long (%d > %d)', len(line), g:karate_linter_max_line_length), 'type': g:karate_linter_max_line_length_level == 'KarateLintError' ? 'E' : 'W'})
        endif

        if g:karate_linter_and_but_rule && line =~ '^\s*But\s'
             call add(report, {'filename': filename, 'lnum': lnum, 'text': "Use 'And' instead of 'But' for consistency", 'type': g:karate_linter_and_but_level == 'KarateLintError' ? 'E' : 'W'})
        endif

        if g:karate_linter_no_space_after_keyword_rule && line =~ '^\s*\(\*\|Given\|When\|Then\|And\|But\)\S'
            call add(report, {'filename': filename, 'lnum': lnum, 'text': 'Missing space after keyword (Given, When, Then, etc.)', 'type': g:karate_linter_no_space_after_keyword_level == 'KarateLintError' ? 'E' : 'W'})
        endif

        if g:karate_linter_call_read_space_rule && line =~ '\bcallread('
             call add(report, {'filename': filename, 'lnum': lnum, 'text': "Use 'call read' instead of 'callread'", 'type': g:karate_linter_call_read_space_level == 'KarateLintError' ? 'E' : 'W'})
        endif

        if g:karate_linter_unclosed_read_rule && line =~ '^\s*\(Given\|When\|Then\|And\|But\|\*\).*read\([^)]*$\)'
             call add(report, {'filename': filename, 'lnum': lnum, 'text': "Unclosed read() function", 'type': g:karate_linter_unclosed_read_level == 'KarateLintError' ? 'E' : 'W'})
        endif
    endfor

    " --- Complex and multi-line rules ---
    if g:karate_linter_missing_examples_rule
        let invalid_lines = s:find_invalid_outlines()
        for lnum in invalid_lines
            call add(report, {'filename': filename, 'lnum': lnum, 'text': "'Scenario Outline' without a corresponding 'Examples' block", 'type': g:karate_linter_missing_examples_level == 'KarateLintError' ? 'E' : 'W'})
        endfor
    endif

    if g:karate_linter_orphaned_examples_rule
        let invalid_lines = s:find_orphaned_examples()
        for lnum in invalid_lines
            call add(report, {'filename': filename, 'lnum': lnum, 'text': "Found 'orphaned' 'Examples' block without 'Scenario Outline'", 'type': g:karate_linter_orphaned_examples_level == 'KarateLintError' ? 'E' : 'W'})
        endfor
    endif

    if g:karate_linter_unclosed_docstring_rule
        let lnum = s:find_unclosed_docstring()
        if lnum > 0
            call add(report, {'filename': filename, 'lnum': lnum, 'text': 'Unclosed DocString (odd number of """). Last one found here.', 'type': g:karate_linter_unclosed_docstring_level == 'KarateLintError' ? 'E' : 'W'})
        endif
    endif

    " --- File structure rules ---
    let buffer_lines = getline(1, '$')
    if g:karate_linter_missing_feature_rule
      if empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Feature:'''))
        call add(report, {'filename': filename, 'lnum': 1, 'text': "Missing mandatory 'Feature:' block in the file", 'type': g:karate_linter_missing_feature_level == 'KarateLintError' ? 'E' : 'W'})
      endif
    endif

    if g:karate_linter_missing_scenario_rule
      if empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario Outline:''')) && empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario:'''))
        call add(report, {'filename': filename, 'lnum': 1, 'text': "Missing 'Scenario:' or 'Scenario Outline:' blocks in the file", 'type': g:karate_linter_missing_scenario_level == 'KarateLintError' ? 'E' : 'W'})
      endif
    endif

    if g:karate_linter_missing_background_rule
      let has_feature = !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Feature:'''))
      let has_scenario = !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario Outline:''')) || !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario:'''))
      if has_feature && has_scenario && empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Background:'''))
        call add(report, {'filename': filename, 'lnum': 1, 'text': "Missing 'Background' block", 'type': g:karate_linter_missing_background_level == 'KarateLintError' ? 'E' : 'W'})
      endif
    endif

    return report
endfunction

function! s:run_linter_and_show_loclist()
    let report = s:generate_lint_report()
    if empty(report)
        echom "[Karate] No issues found."
        return
    endif
    call setloclist(0, [], 'r') " Clear previous list
    call setloclist(0, report, 'a')
    lopen
endfunction

command! KarateLintCheck call s:run_linter_and_show_loclist()

augroup KarateLinter
  autocmd!

  highlight default link KarateLintError Error
  highlight default link KarateLintWarn Todo

  function! s:clear_karate_lint()
    if exists("w:karate_lint_matches")
      for match_id in w:karate_lint_matches
        silent! call matchdelete(match_id)
      endfor
      unlet w:karate_lint_matches
    endif
  endfunction

  function! s:find_invalid_outlines_vim()
    let l:invalid_outline_lines = []
    let l:outline_start_line = 0
    for l:line_num in range(1, line('$'))
      let l:line_text = getline(l:line_num)
      let l:is_outline = l:line_text =~ '^[ \t]*Scenario Outline:'
      let l:is_normal_scenario = l:line_text =~ '^[ \t]*Scenario:' && !l:is_outline
      let l:is_tag = l:line_text =~ '^[ \t]*@'
      let l:is_examples = l:line_text =~ '^[ \t]*Examples:'
      if l:is_normal_scenario || l:is_tag
        if l:outline_start_line > 0
          call add(l:invalid_outline_lines, l:outline_start_line)
          let l:outline_start_line = 0
        endif
      endif
      if l:is_outline
        if l:outline_start_line > 0
            call add(l:invalid_outline_lines, l:outline_start_line)
        endif
        let l:outline_start_line = l:line_num
      endif
      if l:is_examples
        if l:outline_start_line > 0
          let l:outline_start_line = 0
        endif
      endif
    endfor
    if l:outline_start_line > 0
      call add(l:invalid_outline_lines, l:outline_start_line)
    endif
    return l:invalid_outline_lines
  endfunction

  function! s:find_invalid_outlines()
    if !executable('awk')
      return s:find_invalid_outlines_vim()
    endif

    let awk_script = [
    \ 'BEGIN { O = 0 }',
    \ '/^[ \t]*Scenario Outline:/ { if (O > 0) { print O }; O = NR }',
    \ '/^[ \t]*Scenario:/ && !/^[ \t]*Scenario Outline:/ { if (O > 0) { print O; O = 0 } }',
    \ '/^[ \t]*@/ { if (O > 0) { print O; O = 0 } }',
    \ '/^[ \t]*Examples:/ { O = 0 }',
    \ 'END { if (O > 0) { print O } }'
    \ ]
    let awk_command = "awk '" . join(awk_script, " ") . "'"

    let buffer_content = join(getline(1, '$'), "\n")
    let output_lines = systemlist(awk_command, buffer_content)

    return !empty(output_lines) ? map(output_lines, {_, val -> str2nr(val)}) : []
  endfunction

  function! s:find_orphaned_examples_vim()
    let l:orphaned_lines = []
    let l:outline_context_active = 0 " Becomes 1 after 'Scenario Outline'
    for l:line_num in range(1, line('$'))
      let l:line_text = getline(l:line_num)

      let l:is_outline = l:line_text =~ '^[ \t]*Scenario Outline:'
      let l:is_normal_scenario = l:line_text =~ '^[ \t]*Scenario:' && !l:is_outline
      let l:is_tag = l:line_text =~ '^[ \t]*@'
      let l:is_examples = l:line_text =~ '^[ \t]*Examples:'

      " A new scenario or tag resets the expectation for 'Examples'
      if l:is_normal_scenario || l:is_tag
        let l:outline_context_active = 0
      endif

      " A new 'Scenario Outline' starts the context
      if l:is_outline
        let l:outline_context_active = 1
      endif

      if l:is_examples
        if l:outline_context_active
          " This is a valid 'Examples' block, it ends the context
          let l:outline_context_active = 0
        else
          " This is an "orphaned" 'Examples' block
          call add(l:orphaned_lines, l:line_num)
        endif
      endif
    endfor
    return l:orphaned_lines
  endfunction

  function! s:find_orphaned_examples()
    if !executable('awk')
      return s:find_orphaned_examples_vim()
    endif

    let awk_script = [
    \ 'BEGIN { C = 0 }',
    \ '/^[ \t]*Scenario Outline:/ { C = 1 }',
    \ '/^[ \t]*Scenario:/ && !/^[ \t]*Scenario Outline:/ { C = 0 }',
    \ '/^[ \t]*@/ { C = 0 }',
    \ '/^[ \t]*Examples:/ { if (C) { C = 0 } else { print NR } }'
    \ ]
    let awk_command = "awk '" . join(awk_script, " ") . "'"
    let buffer_content = join(getline(1, '$'), "\n")
    let output_lines = systemlist(awk_command, buffer_content)

    return !empty(output_lines) ? map(output_lines, {_, val -> str2nr(val)}) : []
  endfunction

  function! s:find_unclosed_docstring_vim()
    " This is the original pure Vimscript implementation.
    let l:last_occurrence_line = 0
    let l:count = 0
    for l:line_num in range(1, line('$'))
      let l:line_text = getline(l:line_num)
      let l:occurrences_in_line = len(split(l:line_text, '"""', 1)) - 1

      if l:occurrences_in_line > 0
        let l:count += l:occurrences_in_line
        let l:last_occurrence_line = l:line_num
      endif
    endfor

    if l:count % 2 != 0
      return l:last_occurrence_line
    else
      return 0
    endif
  endfunction

  function! s:find_unclosed_docstring()
    " Use ripgrep for fast counting if available.
    " Fallback to VimL implementation if rg is missing.
    if !executable('rg')
      return s:find_unclosed_docstring_vim()
    endif

    let buffer_content = getline(1, '$')
    let content_string = join(buffer_content, "\n")

    " systemlist() passes content_string to rg's stdin.
    let matches = systemlist("rg --no-filename --line-number --fixed-strings '\"\"\"'", content_string)

    if len(matches) % 2 != 0 && !empty(matches)
      let last_match = matches[-1]
      " rg output format: "line_number:column:match"
      let line_num_str = split(last_match, ':')[0]
      return str2nr(line_num_str)
    else
      return 0
    endif
  endfunction

  function! s:setup_karate_lint()
    call s:clear_karate_lint()
    let w:karate_lint_matches = []
    let w:karate_has_errors = 0 " Initialize flag

    let l:cursor_pos = getcurpos() " Save cursor position for search

    " Rule: Tabs
    if g:karate_linter_tabs_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_tabs_level, '\t'))
      if !w:karate_has_errors && g:karate_linter_tabs_level == 'KarateLintError'
        if search('\t', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: Trailing whitespace
    if g:karate_linter_trailing_space_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_trailing_space_level, '\s\+$'))
      if !w:karate_has_errors && g:karate_linter_trailing_space_level == 'KarateLintError'
        if search('\s\+$', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: Line length
    if g:karate_linter_max_line_length > 0
      let l:pattern = '\%>' . g:karate_linter_max_line_length . 'v.\+'
      call add(w:karate_lint_matches, matchadd(g:karate_linter_max_line_length_level, l:pattern))
      if !w:karate_has_errors && g:karate_linter_max_line_length_level == 'KarateLintError'
        if search(l:pattern, 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: 'And' instead of 'But' (style)
    if g:karate_linter_and_but_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_and_but_level, '^\s*But\s'))
      if !w:karate_has_errors && g:karate_linter_and_but_level == 'KarateLintError'
          if search('^\s*But\s', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: No space after keyword
    if g:karate_linter_no_space_after_keyword_rule
      let l:pattern = '^\s*\(\*\|Given\|When\|Then\|And\|But\)\S'
      call add(w:karate_lint_matches, matchadd(g:karate_linter_no_space_after_keyword_level, l:pattern))
      if !w:karate_has_errors && g:karate_linter_no_space_after_keyword_level == 'KarateLintError'
        if search(l:pattern, 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: 'Scenario Outline' without 'Examples'
    if g:karate_linter_missing_examples_rule
      let l:invalid_lines = s:find_invalid_outlines()
      if !empty(l:invalid_lines)
          if g:karate_linter_missing_examples_level == 'KarateLintError'
              let w:karate_has_errors = 1
          endif
          for line_num in l:invalid_lines
              let l:pattern = '\%' . line_num . 'l.\+'
              call add(w:karate_lint_matches, matchadd(g:karate_linter_missing_examples_level, l:pattern))
          endfor
      endif
    endif

    " Rule: 'callread' instead of 'call read'
    if g:karate_linter_call_read_space_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_call_read_space_level, '\bcallread('))
      if !w:karate_has_errors && g:karate_linter_call_read_space_level == 'KarateLintError'
          if search('\bcallread(', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: Unclosed 'read' function
    if g:karate_linter_unclosed_read_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_unclosed_read_level, '^\s*\(Given\|When\|Then\|And\|But\|\*\).*\<read\([^)]*$\)'))
       if !w:karate_has_errors && g:karate_linter_unclosed_read_level == 'KarateLintError'
          if search('^\s*\(Given\|When\|Then\|And\|But\|\*\).*\<read\([^)]*$\)', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Rule: 'Examples' without 'Scenario Outline'
    if g:karate_linter_orphaned_examples_rule
      let l:invalid_lines = s:find_orphaned_examples()
      if !empty(l:invalid_lines)
          if g:karate_linter_orphaned_examples_level == 'KarateLintError'
              let w:karate_has_errors = 1
          endif
          for line_num in l:invalid_lines
              let l:pattern = '\%' . line_num . 'l.\+'
              call add(w:karate_lint_matches, matchadd(g:karate_linter_orphaned_examples_level, l:pattern))
          endfor
      endif
    endif

    " Rule: Unclosed DocString '"""'
    if g:karate_linter_unclosed_docstring_rule
      let l:unclosed_line_num = s:find_unclosed_docstring()
      if l:unclosed_line_num > 0
        if g:karate_linter_unclosed_docstring_level == 'KarateLintError'
          let w:karate_has_errors = 1
        endif
        let l:pattern = '\%' . l:unclosed_line_num . 'l.\+'
        call add(w:karate_lint_matches, matchadd(g:karate_linter_unclosed_docstring_level, l:pattern))
      endif
    endif

    " Rule: Missing 'Feature:'
    if g:karate_linter_missing_feature_rule
      if empty(filter(copy(getline(1, '$')), 'v:val =~ ''^\s*Feature:'''))
        call add(w:karate_lint_matches, matchadd(g:karate_linter_missing_feature_level, '\%1l.\+'))
        if !w:karate_has_errors && g:karate_linter_missing_feature_level == 'KarateLintError'
          let w:karate_has_errors = 1
        endif
      endif
    endif

    " Rule: Missing 'Scenario:' / 'Scenario Outline:'
    if g:karate_linter_missing_scenario_rule
      let buffer_lines = getline(1, '$')
      if empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario Outline:''')) && empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario:'''))
        call add(w:karate_lint_matches, matchadd(g:karate_linter_missing_scenario_level, '\%1l.\+'))
        if !w:karate_has_errors && g:karate_linter_missing_scenario_level == 'KarateLintError'
          let w:karate_has_errors = 1
        endif
      endif
    endif

    " Rule: Missing 'Background:' (warning if Feature and Scenario exist)
    if g:karate_linter_missing_background_rule
      let buffer_lines = getline(1, '$')
      let has_feature = !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Feature:'''))
      let has_scenario = !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario Outline:''')) || !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario:'''))
      if has_feature && has_scenario && empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Background:'''))
        call add(w:karate_lint_matches, matchadd(g:karate_linter_missing_background_level, '\%1l.\+'))
        if !w:karate_has_errors && g:karate_linter_missing_background_level == 'KarateLintError'
          let w:karate_has_errors = 1
        endif
      endif
    endif

    call setpos('.', l:cursor_pos) " Restore cursor position
endfunction

  function! s:has_errors()
    return get(w:, 'karate_has_errors', 0)
  endfunction

  function! s:auto_format_on_save()
    if !g:karate_linter_auto_format_on_save | return | endif
    if s:has_errors() == 0
      let l:save_cursor = getcurpos()
      silent! normal! gg=G
      call setpos('.', l:save_cursor)
    endif
  endfunction

  autocmd BufEnter,BufWinEnter,TextChanged,TextChangedI *.feature call s:setup_karate_lint()
  autocmd BufLeave,WinLeave *.feature call s:clear_karate_lint()
  autocmd BufWritePre *.feature call s:auto_format_on_save()

augroup END

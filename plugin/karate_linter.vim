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


" --- Modern Diagnostics Setup ---
highlight default link KarateLintError Error
highlight default link KarateLintWarn Todo

if has('textprop')
  call prop_type_add('karate_lint_error', { 'highlight': 'KarateLintError' })
  call prop_type_add('karate_lint_warn', { 'highlight': 'KarateLintWarn' })
endif

if has('sign_define')
  sign define KarateLintError text=>> texthl=KarateLintError
  sign define KarateLintWarn text=WW texthl=KarateLintWarn
endif

let s:sign_id = 1000 " Starting sign ID for this plugin
" --- END Modern Diagnostics Setup ---


" --- END CONFIGURATION ---


function! s:AddLineDiag(report, processed_lines, lnum, text, level)
    if has_key(a:processed_lines, a:lnum) | return | endif
    let line_content = getline(a:lnum)
    if empty(line_content) | return | endif
    let start_byte = match(line_content, '\S')
    let start_col = (start_byte > -1) ? (start_byte + 1) : 1
    call add(a:report, {
        \ 'lnum': a:lnum, 'col': start_col, 'end_col': len(line_content) + 1,
        \ 'text': a:text, 'level': a:level })
    let a:processed_lines[a:lnum] = 1
endfunction


function! s:generate_lint_report()
    let report = []
    let filename = bufname('%')

    " --- Simple rules (line-by-line check) ---
    for lnum in range(1, line('$'))
        let line = getline(lnum)

        " Rule: Tabs
        if g:karate_linter_tabs_rule && line =~ '\t'
            let pat = '\t'
            let match_byte_col = match(line, pat)
            if match_byte_col > -1
                let match_byte_len = len(matchstr(line, pat))
                call add(report, {
                    \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                    \ 'text': 'Tabs are not allowed', 'level': g:karate_linter_tabs_level })
            endif
        endif

        " Rule: Trailing whitespace
        if g:karate_linter_trailing_space_rule && line =~ '\s\+$'
            let pat = '\s\+$'
            let match_byte_col = match(line, pat)
            if match_byte_col > -1
                let match_byte_len = len(matchstr(line, pat))
                call add(report, {
                    \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                    \ 'text': 'Trailing whitespace', 'level': g:karate_linter_trailing_space_level })
            endif
        endif

        " Rule: Max line length (byte-based check)
        if g:karate_linter_max_line_length > 0 && len(line) > g:karate_linter_max_line_length
            call add(report, {
                \ 'lnum': lnum, 'col': g:karate_linter_max_line_length + 1, 'end_col': len(line) + 1,
                \ 'text': printf('Line is too long (%d > %d bytes)', len(line), g:karate_linter_max_line_length),
                \ 'level': g:karate_linter_max_line_length_level })
        endif

        " Rule: 'And' instead of 'But'
        if g:karate_linter_and_but_rule && line =~ '^\s*But\s'
            let pat = 'But'
            let match_byte_col = match(line, pat)
            if match_byte_col > -1
                let match_byte_len = len(matchstr(line, pat))
                call add(report, {
                    \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                    \ 'text': "Use 'And' instead of 'But' for consistency", 'level': g:karate_linter_and_but_level })
            endif
        endif

        " Rule: No space after keyword
        if g:karate_linter_no_space_after_keyword_rule && line =~ '^\s*\(\*\|Given\|When\|Then\|And\|But\)\S'
            let pat = '^\s*\zs\(\*\|Given\|When\|Then\|And\|But\)\S'
            let match_byte_col = match(line, pat)
            if match_byte_col > -1
                let match_byte_len = len(matchstr(line, pat))
                call add(report, {
                    \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                    \ 'text': 'Missing space after keyword (Given, When, Then, etc.)', 'level': g:karate_linter_no_space_after_keyword_level })
            endif
        endif

        " Rule: 'callread' instead of 'call read'
        if g:karate_linter_call_read_space_rule && line =~ '\bcallread('
            let pat = '\bcallread('
            let match_byte_col = match(line, pat)
            if match_byte_col > -1
                let match_byte_len = len(matchstr(line, pat))
                call add(report, {
                    \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                    \ 'text': "Use 'call read' instead of 'callread'", 'level': g:karate_linter_call_read_space_level })
            endif
        endif
    endfor

    " --- Complex and multi-line rules (highlighting the whole line) ---
    let l:processed_lines = {} " Helper to avoid duplicate line highlights

    if g:karate_linter_unclosed_read_rule
        let invalid_lines = s:find_unclosed_reads()
        for lnum in invalid_lines
            let line_content = getline(lnum)
            let pat = '\<read\s*([^)]*$'
            let match_byte_col = match(line_content, pat)
            if match_byte_col > -1
                let match_byte_len = len(matchstr(line_content, pat))
                call add(report, {
                    \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                    \ 'text': "Unclosed read() function", 'level': g:karate_linter_unclosed_read_level })
            endif
        endfor
    endif

    if g:karate_linter_missing_examples_rule
        let invalid_lines = s:find_invalid_outlines()
        for lnum in invalid_lines
            call s:AddLineDiag(report, l:processed_lines, lnum, "'Scenario Outline' without a corresponding 'Examples' block", g:karate_linter_missing_examples_level)
        endfor
    endif

    if g:karate_linter_orphaned_examples_rule
        let invalid_lines = s:find_orphaned_examples()
        for lnum in invalid_lines
            call s:AddLineDiag(report, l:processed_lines, lnum, "Found 'orphaned' 'Examples' block without 'Scenario Outline'", g:karate_linter_orphaned_examples_level)
        endfor
    endif

    if g:karate_linter_unclosed_docstring_rule
        let lnum = s:find_unclosed_docstring()
        if lnum > 0
            call s:AddLineDiag(report, l:processed_lines, lnum, 'Unclosed DocString (odd number of """). Last one found here.', g:karate_linter_unclosed_docstring_level)
        endif
    endif

    " --- File structure rules ---
    let buffer_lines = getline(1, '$')
    if g:karate_linter_missing_feature_rule
      if empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Feature:'''))
        call s:AddLineDiag(report, l:processed_lines, 1, "Missing mandatory 'Feature:' block in the file", g:karate_linter_missing_feature_level)
      endif
    endif

    if g:karate_linter_missing_scenario_rule
      if empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario Outline:''')) && empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario:'''))
        call s:AddLineDiag(report, l:processed_lines, 1, "Missing 'Scenario:' or 'Scenario Outline:' blocks in the file", g:karate_linter_missing_scenario_level)
      endif
    endif

    if g:karate_linter_missing_background_rule
      let has_feature = !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Feature:'''))
      let has_scenario = !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario Outline:''')) || !empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Scenario:'''))
      if has_feature && has_scenario && empty(filter(copy(buffer_lines), 'v:val =~ ''^\s*Background:'''))
        call s:AddLineDiag(report, l:processed_lines, 1, "Missing 'Background' block", g:karate_linter_missing_background_level)
      endif
    endif
    
    return report
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

function! s:find_unclosed_reads()
    let invalid_lines = []
    let pattern = '\<read\s*([^)]*$'
    for lnum in range(1, line('$'))
        if getline(lnum) =~# pattern
            call add(invalid_lines, lnum)
        endif
    endfor
    return invalid_lines
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

function! s:run_linter_and_show_loclist()
    let report = s:generate_lint_report()
    if empty(report)
        echom "[Karate] No issues found."
        return
    endif

    " Translate new report format to loclist format
    let loclist_items = []
    for issue in report
        let item = {
            \ 'filename': bufname('%'),
            \ 'lnum': issue.lnum,
            \ 'col': issue.col,
            \ 'text': issue.text,
            \ 'type': issue.level ==# 'KarateLintError' ? 'E' : 'W'
            \ }
        call add(loclist_items, item)
    endfor

    call setloclist(0, [], 'r') " Clear previous list
    call setloclist(0, loclist_items, 'a')
    lopen
endfunction

command! KarateLintCheck call s:run_linter_and_show_loclist()

" --- Modern Diagnostics Engine ---

function! s:clear_diagnostics(bufnr)
    if !has('textprop') | return | endif
    let bufnr = a:bufnr
    if bufnr < 0 | return | endif

    " Clear text properties
    call prop_remove({ 'bufnr': bufnr, 'all': 1, 'type': 'karate_lint_error' })
    call prop_remove({ 'bufnr': bufnr, 'all': 1, 'type': 'karate_lint_warn' })

    " Clear signs
    if has('sign_unplace')
        let sign_group = 'karate_linter_' . bufnr
        call sign_unplace(sign_group, { 'buffer': bufnr })
    endif

    " Clear error cache
    if exists('b:karate_has_errors')
        unlet b:karate_has_errors
    endif
endfunction

function! s:update_diagnostics()
    if !has('textprop') | return | endif
    let bufnr = bufnr('%')
    call s:clear_diagnostics(bufnr)

    let report = s:generate_lint_report()

    " --- Cache error status for auto-format ---
    let b:karate_has_errors = 0
    for issue in report
        if issue.level ==# 'KarateLintError'
            let b:karate_has_errors = 1
            break
        endif
    endfor
    " --- End cache ---

    if empty(report) | return | endif

    let sign_group = 'karate_linter_' . bufnr
    for issue in report
        let prop_type = issue.level ==# 'KarateLintError' ? 'karate_lint_error' : 'karate_lint_warn'
        let sign_name = issue.level ==# 'KarateLintError' ? 'KarateLintError' : 'KarateLintWarn'
        let sign_id = s:sign_id + issue.lnum

        " Add text property for highlighting
        call prop_add(issue.lnum, issue.col, {
            \ 'length': issue.end_col - issue.col,
            \ 'type': prop_type,
            \ 'bufnr': bufnr
            \ })

        " Add sign in the gutter
        if has('sign_place')
            call sign_place(sign_id, sign_group, sign_name, bufnr, { 'lnum': issue.lnum })
        endif
    endfor
endfunction

" --- Auto-formatting on save (re-implemented) ---
function! s:has_errors()
    return get(b:, 'karate_has_errors', 0)
endfunction

function! s:auto_format_on_save()
    if !g:karate_linter_auto_format_on_save | return | endif
    if s:has_errors() == 0
      let l:save_cursor = getcurpos()
      silent! normal! gg=G
      call setpos('.', l:save_cursor)
    endif
endfunction


augroup KarateLinter
  autocmd!
  " Clear diagnostics when leaving the buffer
  autocmd BufLeave,WinLeave *.feature call s:clear_diagnostics(str2nr(expand('<abuf>')))

  " Update diagnostics on events
  autocmd BufEnter,BufWinEnter,TextChanged,TextChangedI *.feature call s:update_diagnostics()
  
  " Auto-format on save
  autocmd BufWritePre *.feature call s:auto_format_on_save()
augroup END

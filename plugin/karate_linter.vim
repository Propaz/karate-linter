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
    \ 'karate_linter_missing_background_level': 'KarateLintWarn',
    \ 'karate_linter_unused_variable_rule': 1,
    \ 'karate_linter_unused_variable_level': 'KarateLintWarn',
    \ 'karate_linter_undefined_placeholder_rule': 1,
    \ 'karate_linter_undefined_placeholder_level': 'KarateLintError',
    \ 'karate_linter_unused_header_rule': 1,
    \ 'karate_linter_unused_header_level': 'KarateLintWarn'
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

if has('signs')
  call sign_define('KarateLintError', {'text': '>>', 'texthl': 'KarateLintError'})
  call sign_define('KarateLintWarn', {'text': 'W>', 'texthl': 'KarateLintWarn'})
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

    let s:simple_line_rules = [
        \  { 'name': 'tabs', 'pattern': '\t', 'text': 'Tabs are not allowed' },
        \  { 'name': 'trailing_space', 'pattern': '\s\+$', 'text': 'Trailing whitespace' },
        \  { 'name': 'and_but', 'pattern': 'But', 'line_pattern': '^\s*But\s', 'text': "Use 'And' instead of 'But' for consistency" },
        \  { 'name': 'no_space_after_keyword', 'pattern': '^\s*\zs\(\*\|Given\|When\|Then\|And\|But\)\S', 'text': 'Missing space after keyword (Given, When, Then, etc.)' },
        \  { 'name': 'call_read_space', 'pattern': '\bcallread(', 'text': "Use 'call read' instead of 'callread'" },
        \ ]

    " --- Simple rules (line-by-line check) ---
    for lnum in range(1, line('$'))
        let line = getline(lnum)

        " --- Data-driven simple rules ---
        for rule in s:simple_line_rules
            if get(g:, 'karate_linter_' . rule.name . '_rule', 0)
                let line_pattern = get(rule, 'line_pattern', rule.pattern)
                if line =~# line_pattern
                    let pat = rule.pattern
                    let match_byte_col = match(line, pat)
                    if match_byte_col > -1
                        let match_byte_len = len(matchstr(line, pat))
                        let level = get(g:, 'karate_linter_' . rule.name . '_level', 'KarateLintError')
                        call add(report, {
                            \ 'lnum': lnum, 'col': match_byte_col + 1, 'end_col': match_byte_col + 1 + match_byte_len,
                            \ 'text': rule.text, 'level': level })
                    endif
                endif
            endif
        endfor

        " Rule: Max line length (byte-based check) - kept separate due to unique logic
        if g:karate_linter_max_line_length > 0 && len(line) > g:karate_linter_max_line_length
            call add(report, {
                \ 'lnum': lnum, 'col': g:karate_linter_max_line_length + 1, 'end_col': len(line) + 1,
                \ 'text': printf('Line is too long (%d > %d bytes)', len(line), g:karate_linter_max_line_length),
                \ 'level': g:karate_linter_max_line_length_level })
        endif
    endfor

    " --- Unused variable check ---
    call extend(report, s:find_unused_variables())

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
            call s:AddLineDiag(report, l:processed_lines, lnum, 'Unclosed DocString. Block started here.', g:karate_linter_unclosed_docstring_level)
        endif
    endif

    if g:karate_linter_undefined_placeholder_rule || g:karate_linter_unused_header_rule
        call extend(report, s:lint_scenario_outlines())
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

function! s:find_all_docstring_ranges()
    let ranges = []
    let in_docstring = 0
    let start_lnum = 0
    let docstring_pattern = '^\s*"""\s*$'

    for lnum in range(1, line('$'))
        if getline(lnum) =~# docstring_pattern
            if !in_docstring
                let start_lnum = lnum
                let in_docstring = 1
            else
                call add(ranges, [start_lnum, lnum])
                let in_docstring = 0
            endif
        endif
    endfor
    return ranges
endfunction

function! s:find_invalid_outlines_vim()
  let l:invalid_outline_lines = []
  let l:outline_start_line = 0
  for l:line_num in range(1, line('$'))
    let l:line_text = getline(l:line_num)
    let l:is_outline = l:line_text =~ '^[ 	]*Scenario Outline:'
    let l:is_normal_scenario = l:line_text =~ '^[ 	]*Scenario:' && !l:is_outline
    let l:is_tag = l:line_text =~ '^[ 	]*@'
    let l:is_examples = l:line_text =~ '^[ 	]*Examples:'
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
  \ '/^[ 	]*Scenario Outline:/ { if (O > 0) { print O }; O = NR }',
  \ '/^[ 	]*Scenario:/ && !/^[ 	]*Scenario Outline:/ { if (O > 0) { print O; O = 0 } }',
  \ '/^[ 	]*@/ { if (O > 0) { print O; O = 0 } }',
  \ '/^[ 	]*Examples:/ { O = 0 }',
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

    let l:is_outline = l:line_text =~ '^[ 	]*Scenario Outline:'
    let l:is_normal_scenario = l:line_text =~ '^[ 	]*Scenario:' && !l:is_outline
    let l:is_tag = l:line_text =~ '^[ 	]*@'
    let l:is_examples = l:line_text =~ '^[ 	]*Examples:'

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
  \ '/^[ 	]*Scenario Outline:/ { C = 1 }',
  \ '/^[ 	]*Scenario:/ && !/^[ 	]*Scenario Outline:/ { C = 0 }',
  \ '/^[ 	]*@/ { C = 0 }',
  \ '/^[ 	]*Examples:/ { if (C) { C = 0 } else { print NR } }'
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

function! s:find_unused_variables()
    let report = []
    if !g:karate_linter_unused_variable_rule | return report | endif

    let lines = getline(1, '$')
    let definitions = {}

    " Pass 1: Find all variable definitions
    let def_pattern = '^\s*\*\s*def\s\+\([a-zA-Z0-9_]\+\)'
    for i in range(len(lines))
        let line = lines[i]
        let match_list = matchlist(line, def_pattern)
        if !empty(match_list)
            let var_name = match_list[1]
            let lnum = i + 1
            let definitions[var_name] = lnum
        endif
    endfor

    if empty(definitions) | return report | endif

    " Pass 2: Find usages for each definition
    let vars_to_check = keys(definitions)
    for var_name in vars_to_check
        let is_used = 0
        let def_lnum = definitions[var_name]
        let usage_pattern = '\<'.var_name.'\>'

        for i in range(len(lines))
            " Don't count the definition line as a usage
            if (i + 1) == def_lnum | continue | endif

            if lines[i] =~# usage_pattern
                let is_used = 1
                break
            endif
        endfor

        if is_used
            call remove(definitions, var_name)
        endif
    endfor

    " Pass 3: Report remaining (unused) variables
    for [var_name, lnum] in items(definitions)
        let line_content = getline(lnum)
        let pat = '\<'.var_name.'\>'
        let match_byte_col = match(line_content, pat)
        if match_byte_col > -1
            let match_byte_len = len(matchstr(line_content, pat))
            call add(report, {
                \ 'lnum': lnum,
                \ 'col': match_byte_col + 1,
                \ 'end_col': match_byte_col + 1 + match_byte_len,
                \ 'text': 'Unused variable: ' . var_name,
                \ 'level': g:karate_linter_unused_variable_level
                \ })
        endif
    endfor

    return report
endfunction

function! s:find_unclosed_docstring_vim()
  let in_docstring = 0
  let start_lnum = 0

  for lnum in range(1, line('$'))
    let line = getline(lnum)

    if in_docstring && line =~ '^\s*\(\* def\|Scenario:\|Scenario Outline:\|Feature:\|@\)'
        return start_lnum
    endif

    let occurrences = len(split(line, '"""', 1)) - 1
    if occurrences > 0
        for _ in range(occurrences)
            if in_docstring
                let in_docstring = 0
                let start_lnum = 0
            else
                let in_docstring = 1
                let start_lnum = lnum
            endif
        endfor
    endif
  endfor

  if in_docstring
    return start_lnum
  endif

  return 0
endfunction

function! s:find_unclosed_docstring()
  return s:find_unclosed_docstring_vim()
endfunction

function! s:trim(text)
    return substitute(a:text, '^\s*\|\s*$', '', 'g')
endfunction

function! s:lint_scenario_outlines()
    let report = []
    let buffer_lines = getline(1, '$')
    let num_lines = len(buffer_lines)

    " --- Step 1: Find all Scenario Outline blocks ---
    let outlines = []
    let current_outline = {}
    let in_outline = 0
    let lnum = 1
    while lnum <= num_lines
        let line = buffer_lines[lnum - 1]

        if line =~ '^\s*Scenario Outline:'
            if in_outline
                let current_outline.end = lnum - 1
                call add(outlines, current_outline)
            endif
            let current_outline = { 'start': lnum }
            let in_outline = 1
        elseif line =~ '^\s*\(@\|Scenario:\)'
            if in_outline
                let current_outline.end = lnum - 1
                call add(outlines, current_outline)
                let in_outline = 0
            endif
        endif
        let lnum += 1
    endwhile
    if in_outline
        let current_outline.end = num_lines
        call add(outlines, current_outline)
    endif

    if empty(outlines)
        return report
    endif

    " --- Step 2-5: Process each outline ---
    for outline in outlines
        let placeholders = {}
        let table_headers = []
        let examples_lnum = -1
        let header_lnum = -1

        " Find Examples: line and header line
        for lnum_in_outline in range(outline.start, outline.end)
            let line = buffer_lines[lnum_in_outline - 1]
            if line =~ '^\s*Examples:'
                let examples_lnum = lnum_in_outline
                let header_lnum_candidate = lnum_in_outline + 1
                while header_lnum_candidate <= outline.end
                    let header_line = buffer_lines[header_lnum_candidate - 1]
                    if header_line =~ '^\s*|.*|$'
                        let header_lnum = header_lnum_candidate
                        break
                    elseif header_line !~ '^\s*$' && header_line !~ '^\s*#'
                        break
                    endif
                    let header_lnum_candidate += 1
                endwhile
                break
            endif
        endfor

        if header_lnum == -1
            continue
        endif

        " Parse headers
        let header_line_content = buffer_lines[header_lnum - 1]
        let parts = split(header_line_content, '|')
        for part in parts
            let header = s:trim(part)
            if !empty(header)
                call add(table_headers, header)
            endif
        endfor

        " Find all placeholders used in the outline body
        let placeholder_pattern = '<\([^>]\+\)>'
        let end_of_steps = (examples_lnum > -1) ? examples_lnum - 1 : outline.end
        for lnum_in_steps in range(outline.start, end_of_steps)
            let line = buffer_lines[lnum_in_steps - 1]
            let match_start = 0
            while match_start >= 0
                let match_idx = match(line, placeholder_pattern, match_start)
                if match_idx != -1
                    let placeholder = matchstr(line, placeholder_pattern, match_idx)
                    let var_name = placeholder[1:-2]
                    if !has_key(placeholders, var_name)
                        let placeholders[var_name] = lnum_in_steps
                    endif
                    let match_start = match_idx + len(placeholder)
                else
                    let match_start = -1
                endif
            endwhile
        endfor

        " Rule: Undefined Placeholder
        if g:karate_linter_undefined_placeholder_rule
            for used_var in keys(placeholders)
                if index(table_headers, used_var) == -1
                    let lnum_of_error = placeholders[used_var]
                    let line_content = buffer_lines[lnum_of_error - 1]
                    let pat = '<' . used_var . '>'
                    let col = match(line_content, pat)
                    let end_col = col + len(pat)

                    call add(report, {
                        \ 'lnum': lnum_of_error,
                        \ 'col': col + 1,
                        \ 'end_col': end_col + 1,
                        \ 'text': "Placeholder '<" . used_var . ">' is not defined in the Examples table.",
                        \ 'level': g:karate_linter_undefined_placeholder_level
                        \ })
                endif
            endfor
        endif

        " Rule: Unused Header
        if g:karate_linter_unused_header_rule
            let used_vars = keys(placeholders)
            for header in table_headers
                if index(used_vars, header) == -1
                    let lnum_of_error = header_lnum
                    let line_content = buffer_lines[lnum_of_error - 1]
                    let pat = '\<'.header.'\>'
                    let col = match(line_content, pat)
                    let start_col = (col > -1) ? col + 1 : 1
                    let end_col = start_col + len(header)
                    call add(report, {
                        \ 'lnum': lnum_of_error,
                        \ 'col': start_col,
                        \ 'end_col': end_col,
                        \ 'text': "Header '" . header . "' is defined in the Examples table but not used in the Scenario Outline.",
                        \ 'level': g:karate_linter_unused_header_level
                        \ })
                endif
            endfor
        endif
    endfor

    return report
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
    if has('signs')
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
        if has('signs')
            call sign_place(sign_id, sign_group, sign_name, bufnr, { 'lnum': issue.lnum })
        endif
    endfor
endfunction

" --- Auto-formatting on save (re-implemented) ---
function! s:has_errors()
    return get(b:, 'karate_has_errors', 0)
endfunction

function! s:smart_auto_format()
    let l:save_cursor = getcurpos()

    " 1. Find and store original content of all docstring blocks
    let docstring_ranges = s:find_all_docstring_ranges()
    let original_blocks = {}
    for range in docstring_ranges
        let start_lnum = range[0]
        let end_lnum = range[1]
        if (end_lnum - start_lnum) > 1
            let original_blocks[start_lnum] = getline(start_lnum + 1, end_lnum - 1)
        else
            let original_blocks[start_lnum] = []
        endif
    endfor

    " 2. Format the entire file with gg=G
    silent! normal! gg=G

    " 3. Restore the original content of the docstring blocks with new indentation
    if !empty(original_blocks)
        for start_lnum in sort(keys(original_blocks), 'n')
            " Find the new end line for the block by moving the cursor first
            let l:inner_save_cursor = getcurpos()
            call cursor(start_lnum + 1, 1)
            let end_lnum = search('^\s*"""\s*$', 'W')
            call setpos('.', l:inner_save_cursor)

            if end_lnum == 0 | continue | endif

            " Delete the garbled content
            if (end_lnum - start_lnum) > 1
                execute (start_lnum + 1) . ',' . (end_lnum - 1) . 'delete _'
            endif

            " Restore original content
            let content_to_restore = original_blocks[start_lnum]
            call append(start_lnum, content_to_restore)
        endfor
    endif

    call setpos('.', l:save_cursor)
endfunction

function! s:auto_format_on_save()
    " If we just formatted JSON, skip this auto-format to prevent messing it up.
    if get(b:, 'karate_just_formatted_json', 0)
        let b:karate_just_formatted_json = 0 " Consume the flag
        return
    endif

    if !g:karate_linter_auto_format_on_save | return | endif
    if s:has_errors() | return | endif

    call s:smart_auto_format()
endfunction


function! s:format_json_in_docstring()
    let cursor_lnum = line('.')
    let docstring_pattern = '^\s*"""\s*$'

    " 1. Find the range of the docstring block around the cursor
    let start_line = search(docstring_pattern, 'bnW')
    if start_line == 0 || start_line > cursor_lnum
        echohl WarningMsg | echo "[Karate] Cursor is not inside a docstring ('''...''') block."
        return
    endif

    let end_line = search(docstring_pattern, 'nW')
    if end_line == 0 || end_line < cursor_lnum
        echohl WarningMsg | echo "[Karate] Cursor is not inside a docstring ('''...''') block."
        return
    endif

    " 2. Extract content and determine indentation
    if (end_line - start_line) <= 1
        echom "[Karate] Docstring is empty, nothing to format."
        return
    endif

    let content_lines = getline(start_line + 1, end_line - 1)
    let json_input = join(content_lines, "\n")

    " Heuristic check: does it look like JSON?
    let first_char_idx = match(json_input, '\S')
    if first_char_idx == -1
        echom "[Karate] Docstring is empty, nothing to format."
        return
    endif
    let first_char = strpart(json_input, first_char_idx, 1)
    if first_char != '{' && first_char != '['
        echohl WarningMsg | echo "[Karate] Block does not appear to contain a JSON object ({}) or array ([]). Aborting formatting."
        return
    endif

    let base_indent = indent(start_line)
    let indent_str = repeat(' ', base_indent)

    " 3. Find and call an external formatter
    let formatted_lines = []
    let l:err = ''
    if executable('jq')
        let formatted_lines = systemlist('jq .', json_input)
        if v:shell_error != 0
            let l:err = '[jq] ' . get(formatted_lines, 0, 'Invalid JSON')
        endif
    elseif executable('python')
        let formatted_lines = systemlist('python -m json.tool', json_input)
        if v:shell_error != 0
            let l:err = '[python] ' . get(formatted_lines, 0, 'Invalid JSON')
        endif
    else
        echohl ErrorMsg | echo "[Karate] No JSON formatter found. Please install 'jq' or 'python'."
        return
    endif

    " Handle formatting errors
    if !empty(l:err)
        echohl ErrorMsg | echo "[Karate] Formatting failed: " . l:err
        return
    endif

    " 4. Replace the old content with the new formatted content
    execute (start_line + 1) . ',' . (end_line - 1) . 'delete'

    " Add indentation to each line of the formatted output
    let indented_lines = map(copy(formatted_lines), { _, val -> indent_str . val })

    call append(start_line, indented_lines)

    " Set a flag to skip the next auto-format-on-save
    let b:karate_just_formatted_json = 1

    echom "[Karate] Formatted JSON block."
endfunction

command! -nargs=0 KarateFmtJson call s:format_json_in_docstring()


augroup KarateLinter
  autocmd!
  " Clear diagnostics when leaving the buffer
  autocmd BufLeave,WinLeave *.feature call s:clear_diagnostics(str2nr(expand('<abuf>')))

  " Update diagnostics on events
  autocmd BufEnter,BufWinEnter,TextChanged,TextChangedI *.feature call s:update_diagnostics()

  " Auto-format on save
  autocmd BufWritePre *.feature call s:auto_format_on_save()
augroup END

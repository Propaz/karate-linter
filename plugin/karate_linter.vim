" ~/.vim/plugin/karate_linter.vim

" Prevent plugin from being loaded multiple times
if exists("g:loaded_karate_linter")
  finish
endif

" matchstrlist() (used by the unused-variable scan) landed in Vim 9.1.0009.
" Fail loudly here instead of throwing E117 on the first lint.
if !has('patch-9.1.9')
  echohl WarningMsg
  echomsg '[Karate] karate_linter.vim requires Vim 9.1.0009 or newer.'
  echohl NONE
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
    \ 'karate_linter_unbalanced_parens_rule': 1,
    \ 'karate_linter_unbalanced_parens_level': 'KarateLintError',
    \ 'karate_linter_unterminated_string_rule': 1,
    \ 'karate_linter_unterminated_string_level': 'KarateLintError',
    \ 'karate_linter_examples_table_rule': 1,
    \ 'karate_linter_examples_table_level': 'KarateLintError',
    \ 'karate_linter_duplicate_feature_rule': 1,
    \ 'karate_linter_duplicate_feature_level': 'KarateLintError',
    \ 'karate_linter_background_placement_rule': 1,
    \ 'karate_linter_background_placement_level': 'KarateLintError',
    \ 'karate_linter_duplicate_scenario_name_rule': 1,
    \ 'karate_linter_duplicate_scenario_name_level': 'KarateLintWarn',
    \ 'karate_linter_placeholder_outside_outline_rule': 1,
    \ 'karate_linter_placeholder_outside_outline_level': 'KarateLintWarn',
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
    \ 'karate_linter_unused_header_level': 'KarateLintWarn',
    \ 'karate_linter_undefined_request_var_rule': 1,
    \ 'karate_linter_undefined_request_var_level': 'KarateLintError',
    \ 'karate_linter_debounce_ms': 150,
    \ 'karate_linter_echo_cursor': 1
    \ }

" Back-compat: the unbalanced-parenthesis check grew out of the old
" read()-only rule and replaces it. An explicit setting of the old option is
" carried over, so existing vimrcs keep working; it must run before the
" defaults below so the alias wins over the default value.
if exists('g:karate_linter_unclosed_read_rule') && !exists('g:karate_linter_unbalanced_parens_rule')
    let g:karate_linter_unbalanced_parens_rule = g:karate_linter_unclosed_read_rule
endif
if exists('g:karate_linter_unclosed_read_level') && !exists('g:karate_linter_unbalanced_parens_level')
    let g:karate_linter_unbalanced_parens_level = g:karate_linter_unclosed_read_level
endif

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


" Built once at load time instead of on every lint pass.
" 'pattern'      - decides where the diagnostic is anchored (column range).
" 'line_pattern' - optional pre-filter deciding whether the rule applies at all.
" 'in_docstring' - set when the rule still applies inside a docstring body.
"                  Docstring bodies are arbitrary JSON/JS/XML payload, not
"                  Karate syntax, so by default rules stay out of them.
"                  Tabs are the exception: they break indentation anywhere.
let s:SIMPLE_LINE_RULES = [
    \  { 'name': 'tabs', 'pattern': '\t', 'text': 'Tabs are not allowed', 'in_docstring': 1 },
    \  { 'name': 'trailing_space', 'pattern': '\s\+$', 'text': 'Trailing whitespace' },
    \  { 'name': 'and_but', 'pattern': 'But', 'line_pattern': '^\s*But\s', 'text': "Use 'And' instead of 'But' for consistency" },
    \  { 'name': 'no_space_after_keyword', 'pattern': '^\s*\zs\(\*\|Given\|When\|Then\|And\|But\)\S', 'text': 'Missing space after keyword (Given, When, Then, etc.)' },
    \  { 'name': 'call_read_space', 'pattern': '\<callread(', 'text': "Use 'call read' instead of 'callread'" },
    \ ]
lockvar! s:SIMPLE_LINE_RULES


" True when a:pattern matches at least one line that is not docstring payload.
" Keeps match()'s early exit: it restarts the search past a docstring hit
" instead of walking the whole buffer.
function! s:has_line_outside_docstring(lines, pattern, docstring_body)
    let idx = 0
    while 1
        let idx = match(a:lines, a:pattern, idx)
        if idx < 0 | return 0 | endif
        if !has_key(a:docstring_body, idx + 1) | return 1 | endif
        let idx += 1
    endwhile
endfunction


" Anchors a whole-line diagnostic.
"
" There is deliberately no 'already reported this line' set any more. It was
" meant to avoid stacking highlights, but two different problems on one line
" are two findings: it silently hid "Missing 'Scenario:'" whenever 'Feature:'
" was missing too, because both anchor to the same line.
"
" An empty anchor line still gets a one-cell span. Previously such a
" diagnostic was dropped outright, so a file that merely started with a blank
" line reported none of its structural problems.
function! s:AddLineDiag(report, lines, lnum, text, level)
    let line_content = get(a:lines, a:lnum - 1, '')
    let start_byte = match(line_content, '\S')
    let start_col = (start_byte > -1) ? (start_byte + 1) : 1
    call add(a:report, {
        \ 'lnum': a:lnum,
        \ 'col': start_col,
        \ 'end_col': max([len(line_content) + 1, start_col + 1]),
        \ 'text': a:text, 'level': a:level })
endfunction

" Where a file-level diagnostic should point: the first line with any content,
" so the highlight lands on real text rather than on leading blank lines.
function! s:first_content_line(lines)
    let idx = match(a:lines, '\S')
    return idx < 0 ? 1 : idx + 1
endfunction


" File-level skeleton checks, all in one pass: a second 'Feature:', a
" 'Background:' in the wrong place or repeated, repeated scenario names, and
" '<placeholder>' left in a plain Scenario where nothing will substitute it.
function! s:lint_structure(lines, docstring_body)
    let report = []
    let dup_feature = g:karate_linter_duplicate_feature_rule
    let background = g:karate_linter_background_placement_rule
    let dup_name = g:karate_linter_duplicate_scenario_name_rule
    let stray_placeholder = g:karate_linter_placeholder_outside_outline_rule
    if !dup_feature && !background && !dup_name && !stray_placeholder
        return report
    endif

    let step_pattern = '\C^\s*\%(\*\|Given\|When\|Then\|And\|But\)\s'
    let feature_seen = 0
    let background_lnum = 0
    let scenario_seen = 0
    let in_plain_scenario = 0
    let names = {}
    let lnum = 0

    for line in a:lines
        let lnum += 1
        if has_key(a:docstring_body, lnum) | continue | endif

        if line =~# '\C^\s*Feature:'
            let in_plain_scenario = 0
            if feature_seen && dup_feature
                call s:AddLineDiag(report, a:lines, lnum,
                    \ "Duplicate 'Feature:' block; a feature file declares exactly one",
                    \ g:karate_linter_duplicate_feature_level)
            endif
            let feature_seen = 1
            continue
        endif

        if line =~# '\C^\s*Background:'
            let in_plain_scenario = 0
            if background
                if background_lnum > 0
                    call s:AddLineDiag(report, a:lines, lnum,
                        \ printf("Duplicate 'Background:' block (the first one is on line %d)", background_lnum),
                        \ g:karate_linter_background_placement_level)
                elseif scenario_seen
                    call s:AddLineDiag(report, a:lines, lnum,
                        \ "'Background:' must come before the first 'Scenario:'",
                        \ g:karate_linter_background_placement_level)
                endif
            endif
            if background_lnum == 0 | let background_lnum = lnum | endif
            continue
        endif

        if line =~# '\C^\s*@'
            let in_plain_scenario = 0
            continue
        endif

        let title = matchlist(line, '\C^\s*Scenario\%( Outline\)\?:\s*\(.\{-}\)\s*$')
        if !empty(title)
            let scenario_seen = 1
            let in_plain_scenario = line !~# '\C^\s*Scenario Outline:'

            if dup_name && !empty(title[1])
                if has_key(names, title[1])
                    call s:AddLineDiag(report, a:lines, lnum,
                        \ printf("Duplicate scenario name '%s' (first used on line %d)", title[1], names[title[1]]),
                        \ g:karate_linter_duplicate_scenario_name_level)
                else
                    let names[title[1]] = lnum
                endif
            endif
            continue
        endif

        " A '<name>' in a plain Scenario is never substituted - it is almost
        " always a step copied out of a Scenario Outline.
        "
        " Only identifier-shaped names count, and a line carrying '</' or '/>'
        " is left alone: Karate allows inline XML such as
        " '* def body = <root>text</root>', whose tags are not placeholders.
        if stray_placeholder && in_plain_scenario && line =~# step_pattern
            \ && stridx(line, '<') >= 0
            \ && stridx(line, '</') < 0 && stridx(line, '/>') < 0
            let start = 0
            while 1
                let [text, from, to] = matchstrpos(line, '<[A-Za-z_][A-Za-z0-9_]*>', start)
                if from < 0 | break | endif
                call add(report, {
                    \ 'lnum': lnum, 'col': from + 1, 'end_col': to + 1,
                    \ 'text': printf("Placeholder '%s' in a plain Scenario is never substituted; use 'Scenario Outline'", text),
                    \ 'level': g:karate_linter_placeholder_outside_outline_level })
                let start = to
            endwhile
        endif
    endfor

    return report
endfunction


function! s:generate_lint_report()
    let report = []
    " Read the buffer exactly once; every rule below works off this list.
    let buffer_lines = getline(1, '$')

    " Resolve rule toggles/levels once instead of per line.
    let active_rules = []
    for rule in s:SIMPLE_LINE_RULES
        if get(g:, 'karate_linter_' . rule.name . '_rule', 0)
            call add(active_rules, {
                \ 'pattern': rule.pattern,
                \ 'line_pattern': get(rule, 'line_pattern', rule.pattern),
                \ 'text': rule.text,
                \ 'in_docstring': get(rule, 'in_docstring', 0),
                \ 'level': get(g:, 'karate_linter_' . rule.name . '_level', 'KarateLintError') })
        endif
    endfor

    let max_len = g:karate_linter_max_line_length

    " --- Simple rules (line-by-line check) ---
    "
    " This loop doubles as the single source of truth for docstring regions.
    " Tracking the state here is free (the loop already visits every line) and
    " every later rule reuses the map instead of re-scanning the buffer.
    "
    " The '"""' delimiters themselves count as Karate syntax, not as body, so
    " trailing whitespace on a delimiter line is still reported.
    let docstring_body = {}
    let in_docstring = 0
    let docstring_start = 0
    let docstring_pattern = '^\s*"""\s*$'

    let lnum = 0
    for line in buffer_lines
        let lnum += 1

        let is_body = 0
        if stridx(line, '"""') >= 0 && line =~# docstring_pattern
            let in_docstring = !in_docstring
            let docstring_start = in_docstring ? lnum : 0
        elseif in_docstring
            let is_body = 1
            let docstring_body[lnum] = 1
        endif

        " --- Data-driven simple rules ---
        for rule in active_rules
            if is_body && !rule.in_docstring | continue | endif
            if line =~# rule.line_pattern
                " matchstrpos() gives position and length in one regex pass
                " (was: =~# + match() + matchstr(), i.e. three passes).
                let [mtext, mstart, mend] = matchstrpos(line, rule.pattern)
                if mstart > -1
                    call add(report, {
                        \ 'lnum': lnum, 'col': mstart + 1, 'end_col': mend + 1,
                        \ 'text': rule.text, 'level': rule.level })
                endif
            endif
        endfor

        " Rule: Max line length (byte-based check) - kept separate due to unique logic.
        " Skipped inside docstrings: a long JSON line usually cannot be
        " wrapped without changing the payload being sent.
        if !is_body && max_len > 0 && len(line) > max_len
            call add(report, {
                \ 'lnum': lnum, 'col': max_len + 1, 'end_col': len(line) + 1,
                \ 'text': printf('Line is too long (%d > %d bytes)', len(line), max_len),
                \ 'level': g:karate_linter_max_line_length_level })
        endif
    endfor

    " --- Unused variable check ---
    call extend(report, s:find_unused_variables(buffer_lines, docstring_body))

    " --- Complex and multi-line rules (highlighting the whole line) ---
    call extend(report, s:lint_delimiters(buffer_lines, docstring_body))

    if g:karate_linter_missing_examples_rule
        let invalid_lines = s:find_invalid_outlines(buffer_lines, docstring_body)
        for lnum in invalid_lines
            call s:AddLineDiag(report, buffer_lines, lnum, "'Scenario Outline' without a corresponding 'Examples' block", g:karate_linter_missing_examples_level)
        endfor
    endif

    if g:karate_linter_orphaned_examples_rule
        let invalid_lines = s:find_orphaned_examples(buffer_lines, docstring_body)
        for lnum in invalid_lines
            call s:AddLineDiag(report, buffer_lines, lnum, "Found 'orphaned' 'Examples' block without 'Scenario Outline'", g:karate_linter_orphaned_examples_level)
        endfor
    endif

    " Derived from the docstring state tracked in the loop above: the block is
    " unclosed only when its closing '"""' never turned up before EOF. The old
    " code guessed instead - it declared the block unclosed as soon as a line
    " inside it looked like a step ('* def', 'Scenario:', '@'), which fires on
    " perfectly valid JSON and JS payloads.
    if g:karate_linter_unclosed_docstring_rule && in_docstring && docstring_start > 0
        call s:AddLineDiag(report, buffer_lines, docstring_start, 'Unclosed DocString. Block started here.', g:karate_linter_unclosed_docstring_level)
    endif

    if g:karate_linter_undefined_placeholder_rule || g:karate_linter_unused_header_rule
        \ || g:karate_linter_examples_table_rule
        call extend(report, s:lint_scenario_outlines(buffer_lines, docstring_body))
    endif

    call extend(report, s:lint_undefined_request_variables(buffer_lines, docstring_body))

    call extend(report, s:lint_structure(buffer_lines, docstring_body))

    " --- File structure rules ---
    " match() on a List stops at the first hit and makes no copy, unlike the
    " previous filter(copy(...)) which scanned the whole buffer six times.
    if g:karate_linter_missing_feature_rule || g:karate_linter_missing_scenario_rule || g:karate_linter_missing_background_rule
      let anchor = s:first_content_line(buffer_lines)
      let has_feature = s:has_line_outside_docstring(buffer_lines, '^\s*Feature:', docstring_body)
      let has_scenario = s:has_line_outside_docstring(buffer_lines, '^\s*Scenario Outline:', docstring_body)
          \ || s:has_line_outside_docstring(buffer_lines, '^\s*Scenario:', docstring_body)

      if g:karate_linter_missing_feature_rule && !has_feature
        call s:AddLineDiag(report, buffer_lines, anchor, "Missing mandatory 'Feature:' block in the file", g:karate_linter_missing_feature_level)
      endif

      if g:karate_linter_missing_scenario_rule && !has_scenario
        call s:AddLineDiag(report, buffer_lines, anchor, "Missing 'Scenario:' or 'Scenario Outline:' blocks in the file", g:karate_linter_missing_scenario_level)
      endif

      if g:karate_linter_missing_background_rule && has_feature && has_scenario
        if !s:has_line_outside_docstring(buffer_lines, '^\s*Background:', docstring_body)
          call s:AddLineDiag(report, buffer_lines, anchor, "Missing 'Background' block", g:karate_linter_missing_background_level)
        endif
      endif
    endif

    return report
endfunction

function! s:find_all_docstring_ranges(lines)
    let ranges = []
    let in_docstring = 0
    let start_lnum = 0
    let docstring_pattern = '^\s*"""\s*$'
    let lnum = 0

    for line in a:lines
        let lnum += 1
        if stridx(line, '"""') < 0 | continue | endif
        if line =~# docstring_pattern
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


" Pure Vim, no subprocess. Previously this shelled out to awk on every single
" keystroke; the \C prefixes keep it case-sensitive exactly like awk was,
" regardless of the user's 'ignorecase'.
function! s:find_invalid_outlines(lines, docstring_body)
  let l:invalid_outline_lines = []
  let l:outline_start_line = 0
  for l:line_num in range(1, len(a:lines))
    if has_key(a:docstring_body, l:line_num) | continue | endif
    let l:line_text = a:lines[l:line_num - 1]
    let l:is_outline = l:line_text =~# '\C^[ 	]*Scenario Outline:'
    let l:is_normal_scenario = l:line_text =~# '\C^[ 	]*Scenario:' && !l:is_outline
    let l:is_tag = l:line_text =~# '\C^[ 	]*@'
    let l:is_examples = l:line_text =~# '\C^[ 	]*Examples:'
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

" Pure Vim, no subprocess. See the note on s:find_invalid_outlines().
function! s:find_orphaned_examples(lines, docstring_body)
  let l:orphaned_lines = []
  let l:outline_context_active = 0 " Becomes 1 after 'Scenario Outline'
  for l:line_num in range(1, len(a:lines))
    if has_key(a:docstring_body, l:line_num) | continue | endif
    let l:line_text = a:lines[l:line_num - 1]

    let l:is_outline = l:line_text =~# '\C^[ 	]*Scenario Outline:'
    let l:is_normal_scenario = l:line_text =~# '\C^[ 	]*Scenario:' && !l:is_outline
    let l:is_tag = l:line_text =~# '\C^[ 	]*@'
    let l:is_examples = l:line_text =~# '\C^[ 	]*Examples:'

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

" --- Unbalanced parentheses in Karate steps ---
"
" Replaces the old read()-only check, which matched '\<read\s*([^)]*$' and so
" missed everything else: nested calls like read(foo(bar), any karate.* call,
" and user JS helpers - while firing on commented-out lines.
"
" Only step lines are considered ('*', Given/When/Then/And/But). Feature and
" Scenario titles, free-text descriptions, tags, tables and whole-line
" comments are therefore out of scope by construction, and docstring bodies
" are excluded by the caller.

let s:CLOSERS = { ')': '(', '}': '{', ']': '[' }

" A complete string literal in any of Karate's three quote styles, backslash
" escapes included. Used to blank strings out before the cheap balance test.
let s:STRING_LITERAL = '\%('
    \ . '"\%([^"\\]\|\\.\)*"'
    \ . '\|' . '''\%([^''\\]\|\\.\)*'''
    \ . '\|' . '`\%([^`\\]\|\\.\)*`'
    \ . '\)'

" Cheap, sound pre-check: is this line worth a character-by-character scan?
"
" The scan is an interpreted loop over every byte, and on a realistic Karate
" file nearly every step contains a quote - running it everywhere cost more
" than the entire rest of the linter. This does the same job with two
" substitute() calls and a collapse loop over a handful of bracket
" characters, all in C.
"
" It never misses a problem: complete strings are blanked out, so a quote left
" over means an unterminated one, and matched bracket pairs are collapsed
" until nothing more can be removed, so anything left over is genuinely
" unbalanced (')(' included, which a simple count comparison would miss).
function! s:line_may_be_unbalanced(line)
    let stripped = substitute(a:line, s:STRING_LITERAL, '', 'g')
    let stripped = substitute(stripped, ':\@<!//.*$', '', '')

    " A quote surviving the strip had no partner.
    if stripped =~# '[''"`]' | return 1 | endif

    let brackets = substitute(stripped, '[^(){}[\]]', '', 'g')
    while !empty(brackets)
        let previous = brackets
        let brackets = substitute(brackets, '()\|{}\|\[\]', '', 'g')
        if brackets ==# previous | break | endif
    endwhile

    return !empty(brackets)
endfunction

" Scans a step line for the first delimiter problem. Returns {} when the line
" is well formed, otherwise one of:
"   { 'kind': 'string',  'idx': <byte>, 'char': <quote> }
"   { 'kind': 'bracket', 'idx': <byte>, 'char': '(' / '{' / '[' }
"
" Delimiters inside string literals do not count, and a trailing JavaScript
" line comment is ignored - except for the '//' in a URL such as http://x.
function! s:scan_delimiters(line)
    let line_len = len(a:line)
    let open_stack = []
    let quote = ''
    let quote_idx = -1
    let i = 0

    while i < line_len
        let c = a:line[i]

        if !empty(quote)
            " Inside a string: only an escape or the closing quote matter.
            if c ==# '\'
                let i += 2
                continue
            endif
            if c ==# quote
                let quote = ''
            endif
            let i += 1
            continue
        endif

        if c ==# "'" || c ==# '"' || c ==# '`'
            let quote = c
            let quote_idx = i
            let i += 1
            continue
        endif

        if c ==# '/' && i + 1 < line_len && a:line[i + 1] ==# '/'
            if i == 0 || a:line[i - 1] !=# ':'
                break
            endif
            let i += 2
            continue
        endif

        if c ==# '(' || c ==# '{' || c ==# '['
            call add(open_stack, { 'char': c, 'idx': i })
        elseif has_key(s:CLOSERS, c)
            " A closer that does not match the innermost opener closes
            " nothing, the same way a stray ')' always has: it must not cancel
            " out a bracket that really is left open.
            if !empty(open_stack) && open_stack[-1].char ==# s:CLOSERS[c]
                call remove(open_stack, -1)
            endif
        endif

        let i += 1
    endwhile

    " An unterminated string swallows the rest of the line, so it is reported
    " alone: any bracket after the opening quote was never really seen, and
    " piling those on top would just bury the root cause.
    if !empty(quote)
        return { 'kind': 'string', 'idx': quote_idx, 'char': quote }
    endif
    if !empty(open_stack)
        return { 'kind': 'bracket', 'idx': open_stack[0].idx, 'char': open_stack[0].char }
    endif
    return {}
endfunction

function! s:lint_delimiters(lines, docstring_body)
    let report = []
    let brackets_on = g:karate_linter_unbalanced_parens_rule
    let strings_on = g:karate_linter_unterminated_string_rule
    if !brackets_on && !strings_on | return report | endif

    let step_pattern = '\C^\s*\%(\*\|Given\|When\|Then\|And\|But\)\s'
    let lnum = 0

    for line in a:lines
        let lnum += 1
        if has_key(a:docstring_body, lnum) | continue | endif

        " Cheapest test first: a line with no delimiter at all cannot be
        " unbalanced, and that covers most 'And match a == b' style steps.
        if line !~# '[(){}[\]''"`]' | continue | endif
        if line !~# step_pattern | continue | endif
        if !s:line_may_be_unbalanced(line) | continue | endif

        " Only reached for a line that really is broken, so the cost of the
        " character scan - which is what pins down the exact column - is paid
        " once per problem instead of once per step.
        let problem = s:scan_delimiters(line)
        if empty(problem) | continue | endif

        if problem.kind ==# 'string'
            if !strings_on | continue | endif
            call add(report, {
                \ 'lnum': lnum,
                \ 'col': problem.idx + 1,
                \ 'end_col': len(line) + 1,
                \ 'text': printf('Unterminated string literal (no closing %s)', problem.char),
                \ 'level': g:karate_linter_unterminated_string_level
                \ })
            continue
        endif

        if !brackets_on | continue | endif

        if problem.char ==# '('
            " Only report call parentheses: 'name(' or 'name ('. A bare
            " grouping paren is left alone, per the agreed scope. Braces and
            " brackets need no such test: in Karate they are always data
            " literals, never grouping.
            let before = strpart(line, 0, problem.idx)
            let [name_text, name_start, name_end] = matchstrpos(before, '[A-Za-z_$][A-Za-z0-9_$.]*\s*$')
            if name_start < 0 | continue | endif

            let text = printf("Unclosed '(' in call to '%s'", substitute(name_text, '\s\+$', '', ''))
            let col = name_start + 1
        else
            let text = printf("Unclosed '%s'", problem.char)
            let col = problem.idx + 1
        endif

        call add(report, {
            \ 'lnum': lnum,
            \ 'col': col,
            \ 'end_col': len(line) + 1,
            \ 'text': text,
            \ 'level': g:karate_linter_unbalanced_parens_level
            \ })
    endfor

    return report
endfunction

function! s:find_unused_variables(lines, docstring_body)
    let report = []
    if !g:karate_linter_unused_variable_rule | return report | endif

    let definitions = {}

    " Pass 1: Find all variable definitions.
    " Docstring payload is skipped here: a '* def x' line inside a JSON or JS
    " block is not a Karate definition. Note that only DEFINITIONS are
    " skipped - usages are deliberately still counted everywhere, because
    " Karate evaluates embedded expressions such as '#(userId)' inside
    " docstrings, and those are genuine usages.
    let def_pattern = '^\s*\*\s*def\s\+\([a-zA-Z0-9_]\+\)'
    for i in range(len(a:lines))
        if has_key(a:docstring_body, i + 1) | continue | endif
        let line = a:lines[i]
        let match_list = matchlist(line, def_pattern)
        if !empty(match_list)
            let var_name = match_list[1]
            let lnum = i + 1
            let definitions[var_name] = lnum
        endif
    endfor

    if empty(definitions) | return report | endif

    " Pass 2: Find usages for ALL definitions in a single scan of the buffer.
    "
    " The previous implementation re-scanned every line for every variable
    " (O(lines * variables)). matchstrlist() searches once with an alternation
    " of all names and returns every match with its list index, in C.
    " \< \> keep the same word-boundary semantics as the old '\<name\>' test,
    " and \C matches the old case-sensitive =~# comparison.
    let unused = copy(definitions)
    let usage_pattern = '\C\<\%(' . join(keys(definitions), '\|') . '\)\>'

    for m in matchstrlist(a:lines, usage_pattern)
        " A definition line is not a usage of the name it defines (but it may
        " well be a usage of some other variable, e.g. '* def b = a + 1').
        if get(definitions, m.text, -1) == m.idx + 1 | continue | endif

        if has_key(unused, m.text)
            call remove(unused, m.text)
            if empty(unused) | break | endif
        endif
    endfor

    " Pass 3: Report remaining (unused) variables.
    " Sorted by line: dictionary iteration order is unspecified in Vim, so the
    " previous version emitted diagnostics (and loclist rows) in arbitrary order.
    let leftovers = items(unused)
    call sort(leftovers, {x, y -> x[1] - y[1]})

    for [var_name, lnum] in leftovers
        let [mtext, mstart, mend] = matchstrpos(a:lines[lnum - 1], '\C\<' . var_name . '\>')
        if mstart > -1
            call add(report, {
                \ 'lnum': lnum,
                \ 'col': mstart + 1,
                \ 'end_col': mend + 1,
                \ 'text': 'Unused variable: ' . var_name,
                \ 'level': g:karate_linter_unused_variable_level
                \ })
        endif
    endfor

    return report
endfunction

function! s:trim(text)
    return substitute(a:text, '^\s*\|\s*$', '', 'g')
endfunction

" Splits a Gherkin table row into cells, keeping the byte position of each
" one. Positions come from the parse instead of a later search, so no pattern
" is ever built out of user text.
"
" Returns [] for a line that is not a table row. Empty cells are preserved:
" they still count as columns. A pipe escaped as '\|' is cell content.
function! s:parse_table_row(line)
    let bars = []
    let i = 0
    let line_len = len(a:line)
    while i < line_len
        if a:line[i] ==# '\'
            let i += 2
            continue
        endif
        if a:line[i] ==# '|'
            call add(bars, i)
        endif
        let i += 1
    endwhile

    if len(bars) < 2 | return [] | endif

    let cells = []
    let idx = 0
    while idx < len(bars) - 1
        let start = bars[idx] + 1
        let raw = strpart(a:line, start, bars[idx + 1] - start)
        let lead = matchstr(raw, '^\s*')
        let text = s:trim(raw)
        let col = start + len(lead) + 1
        " Empty cells get a one-column span so the range stays highlightable.
        call add(cells, {
            \ 'text': text,
            \ 'col': col,
            \ 'end_col': col + (empty(text) ? 1 : len(text)) })
        let idx += 1
    endwhile
    return cells
endfunction

" Checks one Examples table for internal consistency: duplicated column names,
" data rows whose cell count disagrees with the header, and a header with no
" data rows under it (an outline that silently never runs).
function! s:lint_examples_table(lines, docstring_body, header_lnum, outline_end, header_cells)
    let report = []
    let level = g:karate_linter_examples_table_level

    " Duplicate column names: the later one wins in Gherkin, so the earlier
    " column is silently unreachable.
    let seen = {}
    for cell in a:header_cells
        if empty(cell.text) | continue | endif
        if has_key(seen, cell.text)
            call add(report, {
                \ 'lnum': a:header_lnum, 'col': cell.col, 'end_col': cell.end_col,
                \ 'text': printf("Duplicate Examples column '%s'", cell.text),
                \ 'level': level })
        endif
        let seen[cell.text] = 1
    endfor

    " Data rows run contiguously under the header until the table stops.
    let expected = len(a:header_cells)
    let rows = 0
    let lnum = a:header_lnum + 1

    while lnum <= a:outline_end
        if has_key(a:docstring_body, lnum) | break | endif
        let line = a:lines[lnum - 1]
        if line =~ '^\s*$' || line =~ '^\s*#'
            let lnum += 1
            continue
        endif
        if line !~ '^\s*|.*|$' | break | endif

        let rows += 1
        let cells = s:parse_table_row(line)
        if len(cells) != expected
            call add(report, {
                \ 'lnum': lnum,
                \ 'col': match(line, '\S') + 1,
                \ 'end_col': len(line) + 1,
                \ 'text': printf('Examples row has %d cell%s, the header has %d',
                \                len(cells), len(cells) == 1 ? '' : 's', expected),
                \ 'level': level })
        endif
        let lnum += 1
    endwhile

    if rows == 0
        let header_line = a:lines[a:header_lnum - 1]
        call add(report, {
            \ 'lnum': a:header_lnum,
            \ 'col': match(header_line, '\S') + 1,
            \ 'end_col': len(header_line) + 1,
            \ 'text': 'Examples table has no data rows',
            \ 'level': level })
    endif

    return report
endfunction


" Docstring payload is skipped when locating block boundaries and the Examples
" table, but NOT when collecting '<placeholder>' usages: Gherkin substitutes
" Examples values inside docstrings too, so a placeholder used only in a JSON
" payload is a real usage of that header.
function! s:lint_scenario_outlines(buffer_lines, docstring_body)
    let report = []
    let num_lines = len(a:buffer_lines)

    " --- Step 1: Find all Scenario Outline blocks ---
    let outlines = []
    let current_outline = {}
    let in_outline = 0
    let lnum = 1
    while lnum <= num_lines
        if has_key(a:docstring_body, lnum)
            let lnum += 1
            continue
        endif
        let line = a:buffer_lines[lnum - 1]

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
            if has_key(a:docstring_body, lnum_in_outline) | continue | endif
            let line = a:buffer_lines[lnum_in_outline - 1]
            if line =~ '^\s*Examples:'
                let examples_lnum = lnum_in_outline
                let header_lnum_candidate = lnum_in_outline + 1
                while header_lnum_candidate <= outline.end
                    let header_line = a:buffer_lines[header_lnum_candidate - 1]
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

        " Rule: Examples table consistency.
        " Only reached when an 'Examples:' block exists at all - an outline
        " with no Examples is the missing_examples rule's business.
        if g:karate_linter_examples_table_rule && examples_lnum > -1 && header_lnum == -1
            let examples_line = a:buffer_lines[examples_lnum - 1]
            let indent = match(examples_line, '\S')
            call add(report, {
                \ 'lnum': examples_lnum,
                \ 'col': (indent > -1 ? indent : 0) + 1,
                \ 'end_col': len(examples_line) + 1,
                \ 'text': "'Examples' block has no table",
                \ 'level': g:karate_linter_examples_table_level
                \ })
        endif

        if header_lnum == -1
            continue
        endif

        " Parse headers. Empty cells are kept in header_cells (they still count
        " as columns) but stay out of table_headers, which is the list of names
        " a placeholder can refer to.
        let header_cells = s:parse_table_row(a:buffer_lines[header_lnum - 1])
        for cell in header_cells
            if !empty(cell.text)
                call add(table_headers, cell.text)
            endif
        endfor

        if g:karate_linter_examples_table_rule
            call extend(report, s:lint_examples_table(
                \ a:buffer_lines, a:docstring_body, header_lnum, outline.end, header_cells))
        endif

        " Find all placeholders used in the outline body
        let placeholder_pattern = '<\([^<>]\+\)>'
        let end_of_steps = (examples_lnum > -1) ? examples_lnum - 1 : outline.end
        for lnum_in_steps in range(outline.start, end_of_steps)
            let line = a:buffer_lines[lnum_in_steps - 1]
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
                    let line_content = a:buffer_lines[lnum_of_error - 1]

                    " stridx(), not match(): the placeholder name comes from
                    " the file and may contain regular-expression
                    " metacharacters. Building a pattern out of it found the
                    " wrong offset, or none at all - and a col of 0 then made
                    " prop_add() throw E964 and kill the whole render.
                    let needle = '<' . used_var . '>'
                    let idx = stridx(line_content, needle)
                    if idx < 0 | continue | endif

                    call add(report, {
                        \ 'lnum': lnum_of_error,
                        \ 'col': idx + 1,
                        \ 'end_col': idx + 1 + len(needle),
                        \ 'text': "Placeholder '<" . used_var . ">' is not defined in the Examples table.",
                        \ 'level': g:karate_linter_undefined_placeholder_level
                        \ })
                endif
            endfor
        endif

        " Rule: Unused Header
        " Positions come from the parsed cells, so no pattern is built out of
        " the header text either.
        if g:karate_linter_unused_header_rule
            let used_vars = keys(placeholders)
            for cell in header_cells
                if empty(cell.text) | continue | endif
                if index(used_vars, cell.text) == -1
                    call add(report, {
                        \ 'lnum': header_lnum,
                        \ 'col': cell.col,
                        \ 'end_col': cell.end_col,
                        \ 'text': "Header '" . cell.text . "' is defined in the Examples table but not used in the Scenario Outline.",
                        \ 'level': g:karate_linter_unused_header_level
                        \ })
                endif
            endfor
        endif
    endfor

    return report
endfunction

function! s:lint_undefined_request_variables(lines, docstring_body)
    let report = []
    if !g:karate_linter_undefined_request_var_rule | return report | endif

    let defined_vars = {} " Using a dictionary as a set

    let def_pattern = '^\s*\*\s*def\s\+\([a-zA-Z0-9_]\+\)'
    let request_pattern = '^\s*\(And\|Given\|When\|Then\|\*\)\s\+request\s\+\([a-zA-Z0-9_]\+\)\s*\(#.*\)\?$'

    " Both halves parse Karate statements, so docstring payload is skipped
    " entirely here - a 'Given request x' line inside a JSON block is text.
    for lnum in range(1, len(a:lines))
        if has_key(a:docstring_body, lnum) | continue | endif
        let line = a:lines[lnum - 1]

        " Check for 'request' usage FIRST
        let req_match = matchlist(line, request_pattern)
        if !empty(req_match)
            let var_name = req_match[2]
            if !has_key(defined_vars, var_name)
                " It's an error. Find column for highlighting.
                let line_part_before_var = matchstr(line, '^\s*\(And\|Given\|When\|Then\|\*\)\s\+request\s\+')
                let col = len(line_part_before_var)

                call add(report, {
                    \ 'lnum': lnum,
                    \ 'col': col + 1,
                    \ 'end_col': col + 1 + len(var_name),
                    \ 'text': "Variable '" . var_name . "' used with 'request' is not defined before this line.",
                    \ 'level': g:karate_linter_undefined_request_var_level
                    \ })
            endif
        endif

        " THEN check for definition, so it's available for the next lines
        let def_match = matchlist(line, def_pattern)
        if !empty(def_match)
            let var_name = def_match[1]
            let defined_vars[var_name] = 1
        endif
    endfor

    return report
endfunction

" Public entry point for tests and debugging: returns the raw diagnostic
" report (list of {lnum, col, end_col, text, level}) for the current buffer.
function! KarateLinterReport() abort
    return s:generate_lint_report()
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
endfunction

function! s:update_diagnostics()
    let bufnr = bufnr('%')
    call s:clear_diagnostics(bufnr)

    let report = s:generate_lint_report()

    " --- Cache error status for auto-format ---
    " Computed before the 'textprop' guard below on purpose: without text
    " properties s:has_errors() used to always answer 0, so auto-format ran
    " on files the linter had rejected.
    let b:karate_has_errors = 0
    for issue in report
        if issue.level ==# 'KarateLintError'
            let b:karate_has_errors = 1
            break
        endif
    endfor
    " --- End cache ---

    " Index by line so the cursor handler is a dictionary lookup rather than a
    " scan of the report on every cursor movement.
    let b:karate_diagnostics = {}
    for issue in report
        if !has_key(b:karate_diagnostics, issue.lnum)
            let b:karate_diagnostics[issue.lnum] = []
        endif
        call add(b:karate_diagnostics[issue.lnum], issue)
    endfor

    " Note: no echoing from here. This runs from the buffer-load and
    " buffer-write autocommands too, where the cursor has not been placed yet
    " and Vim is about to print its own message - a second message on top of
    " that produces a 'Press ENTER' prompt. The debounce timer refreshes the
    " message instead; see s:on_lint_timer().

    if !has('textprop') || empty(report) | return | endif

    let sign_group = 'karate_linter_' . bufnr
    for issue in report
        " Defence in depth: a rule that computes a bad column must not be able
        " to abort the render for the entire buffer, which is what an E964 out
        " of prop_add() used to do.
        if issue.col < 1 || issue.end_col <= issue.col | continue | endif

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

" --- Message for the line under the cursor ---
"
" Signs and highlights show that something is wrong but not what. This echoes
" the message for the current line in the command line.

" Truncate to a display width. printf('%.<n>S') counts bytes for the precision,
" which cuts multibyte text (a Cyrillic variable name) far too early, so the
" width is measured properly here.
function! s:truncate_to_width(text, maxwidth)
    if a:maxwidth <= 0 | return '' | endif
    if strdisplaywidth(a:text) <= a:maxwidth | return a:text | endif

    let out = a:text
    while !empty(out) && strdisplaywidth(out . '...') > a:maxwidth
        let out = strcharpart(out, 0, strchars(out) - 1)
    endwhile
    return out . '...'
endfunction

" How much room the command line really has. A message that fills the last
" screen line makes Vim prompt with 'Press ENTER', which would be far more
" annoying than a clipped message.
function! s:echo_width()
    let width = &columns - 1
    if &showcmd | let width -= 11 | endif
    return width
endfunction

" Of the diagnostics on a line, the most relevant one: whatever covers the
" cursor column, else errors before warnings, else the leftmost.
function! s:pick_diagnostic(diags, col)
    let best = {}
    for issue in a:diags
        if a:col >= issue.col && a:col < issue.end_col
            if empty(best) || (issue.level ==# 'KarateLintError' && best.level !=# 'KarateLintError')
                let best = issue
            endif
        endif
    endfor
    if !empty(best) | return best | endif

    for issue in a:diags
        if empty(best)
            \ || (issue.level ==# 'KarateLintError' && best.level !=# 'KarateLintError')
            \ || (issue.level ==# best.level && issue.col < best.col)
            let best = issue
        endif
    endfor
    return best
endfunction

function! s:format_diagnostic_message(diags, col, maxwidth)
    if empty(a:diags) | return '' | endif

    let issue = s:pick_diagnostic(a:diags, a:col)
    let tag = issue.level ==# 'KarateLintError' ? 'E' : 'W'
    let extra = len(a:diags) > 1 ? printf('  (+%d more)', len(a:diags) - 1) : ''

    " The suffix is kept whole; only the message text is clipped.
    let prefix = '[karate] ' . tag . ': '
    let budget = a:maxwidth - strdisplaywidth(prefix) - strdisplaywidth(extra)
    return prefix . s:truncate_to_width(issue.text, budget) . extra
endfunction

function! s:echo_diagnostic()
    if !g:karate_linter_echo_cursor | return | endif

    " Never write to the command line while inserting or replacing: it fights
    " with the completion menu, and the debounce timer can fire mid-insert.
    if mode() =~# '^[iR]' | return | endif

    let diags = get(get(b:, 'karate_diagnostics', {}), line('.'), [])
    let message = s:format_diagnostic_message(diags, col('.'), s:echo_width())

    " Only touch the command line when the message actually changes: echoing on
    " every cursor movement would keep wiping messages from other plugins.
    if message ==# get(b:, 'karate_echoed', '') | return | endif
    let b:karate_echoed = message

    if empty(message)
        echo ''
        return
    endif

    let level = s:pick_diagnostic(diags, col('.')).level
    execute 'echohl' (level ==# 'KarateLintError' ? 'ErrorMsg' : 'WarningMsg')
    echo message
    echohl NONE
endfunction

" --- Debounced updates ---
"
" TextChanged/TextChangedI fire on every single keystroke. Re-linting the
" whole buffer that often is pure waste: coalesce bursts of edits into one
" pass once typing pauses.

let s:lint_timer = -1

function! s:cancel_pending_update()
    if s:lint_timer != -1
        call timer_stop(s:lint_timer)
        let s:lint_timer = -1
    endif
endfunction

function! s:on_lint_timer(bufnr, timer)
    let s:lint_timer = -1
    " The user may have switched buffers while the timer was pending; the new
    " buffer gets its own lint from BufWinEnter, so just drop this one.
    if bufnr('%') != a:bufnr | return | endif
    call s:update_diagnostics()

    " An edit can add or remove a diagnostic on the line the cursor is already
    " sitting on, and that produces no CursorMoved. This is the one place it
    " is safe to refresh the message: the user is idle, the buffer is loaded,
    " and Vim is not about to print a message of its own.
    call s:echo_diagnostic()
endfunction

function! s:schedule_update()
    call s:cancel_pending_update()
    let delay = get(g:, 'karate_linter_debounce_ms', 150)
    if delay <= 0
        call s:update_diagnostics()
        return
    endif
    let bufnr = bufnr('%')
    let s:lint_timer = timer_start(delay, function('s:on_lint_timer', [bufnr]))
endfunction

" Run any pending lint right now. Needed before anything that reads the
" cached error state (auto-format on save), otherwise a debounced edit could
" still be in flight and s:has_errors() would answer from stale data.
function! s:flush_pending_update()
    call s:cancel_pending_update()
    call s:update_diagnostics()
endfunction

" --- Auto-formatting on save (re-implemented) ---
function! s:has_errors()
    return get(b:, 'karate_has_errors', 0)
endfunction

function! s:smart_auto_format()
    let l:save_cursor = getcurpos()

    " 1. Find and store original content of all docstring blocks
    let docstring_ranges = s:find_all_docstring_ranges(getline(1, '$'))
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
    " Apply any debounced edit before anything reads the cached error state,
    " so the buffer being written is judged as it is right now. Done first and
    " unconditionally: after a save the gutter should be current even when
    " auto-formatting itself is turned off.
    call s:flush_pending_update()

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


function! s:replace_tabs_with_spaces()
    " Save cursor and view to prevent screen jump
    let l:save_cursor = getcurpos()
    let l:view = winsaveview()

    " Get number of spaces from shiftwidth, default to 4 if it's 0
    let l:num_spaces = &shiftwidth > 0 ? &shiftwidth : 4
    let l:space_string = repeat(' ', l:num_spaces)

    " Perform replacement
    silent! execute '%s/\t/' . l:space_string . '/g'

    " Restore view and cursor
    call winrestview(l:view)
    call setpos('.', l:save_cursor)
    echom "[Karate] Replaced tabs with spaces."
endfunction

command! KarateTabsToSpaces call s:replace_tabs_with_spaces()


augroup KarateLinter
  autocmd!
  " Lint when the buffer becomes visible or is (re)loaded.
  " Text properties and signs are buffer-local and survive window switches, so
  " there is no longer a BufLeave/WinLeave teardown followed by a full
  " recompute on BufEnter - that was doing the whole job twice per switch.
  autocmd BufWinEnter,BufReadPost *.feature call s:update_diagnostics()

  " Debounced re-lint while editing.
  autocmd TextChanged,TextChangedI *.feature call s:schedule_update()

  " Message for the line under the cursor. Normal/visual mode only: echoing
  " while inserting fights with the completion menu.
  autocmd CursorMoved *.feature call s:echo_diagnostic()

  " Nothing pending should outlive the buffer.
  autocmd BufUnload *.feature call s:cancel_pending_update()

  " Auto-format on save
  autocmd BufWritePre *.feature call s:auto_format_on_save()
augroup END

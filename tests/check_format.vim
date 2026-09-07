" Checks the formatting paths: the indent pass, the fixup pass, :KarateFormat,
" :KarateFmtJson and :KarateTabsToSpaces.
"
" The indentation is asserted line by line, on purpose. The first version of
" this file asserted only that lines outside the docstrings had *changed* --
" which was green precisely because the formatter was flattening the whole
" file to column 0. An assertion that something moved is not an assertion that
" it moved to the right place.
"
"   vim -Nu NONE -es -S tests/check_format.vim

set nocompatible noignorecase nomore noswapfile
set encoding=utf-8

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
" The engine is loaded lazily from autoload/, so the repo has to be on
" the runtimepath before the plugin file is sourced.
let s:rtp = substitute(s:root, '\', '/', 'g')
execute 'set runtimepath^=' . escape(s:rtp, ' ,')
execute 'source ' . fnameescape(s:root . '/plugin/karate_linter.vim')

let s:out = []
let s:fail = 0

function! s:Ok(label, got, want) abort
    if a:got ==# a:want
        call add(s:out, printf('  ok   %-46s %s', a:label, string(a:got)))
    else
        let s:fail += 1
        call add(s:out, printf('  FAIL %-46s\n         got  %s\n         want %s',
            \ a:label, string(a:got), string(a:want)))
    endif
endfunction

" Line numbers of the """ delimiters in a list of lines.
function! s:Delims(lines) abort
    let l:d = []
    for l:i in range(len(a:lines))
        if a:lines[l:i] =~# '^\s*"""\s*$'
            call add(l:d, l:i + 1)
        endif
    endfor
    return l:d
endfunction

" Every docstring body, dedented by the indentation of its opening delimiter
" -- which is the string Karate actually receives. Formatting may move a block
" around, but this must come back identical.
function! s:Payload(lines) abort
    let l:res = []
    let l:inside = 0
    let l:base = 0
    for l:line in a:lines
        if l:line =~# '^\s*"""\s*$'
            if !l:inside
                let l:base = strlen(matchstr(l:line, '^\s*'))
            endif
            let l:inside = !l:inside
            continue
        endif
        if l:inside
            call add(l:res, strpart(l:line, l:base))
        endif
    endfor
    return l:res
endfunction

" --- 1. The indent pass rebuilds the file, line for line ---
call add(s:out, '--- indent pass')
let s:file = s:root . '/tests/fixtures/32_indent_rebuild.feature'
let s:orig = readfile(s:file)

" This is the contract. Feature at 0, description and Background and Scenario
" at 4, steps and Examples at 8, table rows at 12; a tag and a comment take
" the level of whatever follows them; the docstring delimiters go to the step
" level and the body moves with them, keeping its own internal shape.
let s:want = [
    \ 'Feature: indentation is rebuilt by the plugin, not by =',
    \ '    Free text under Feature, wrongly at column 0.',
    \ '    A second description line, wrongly too deep.',
    \ '',
    \ '    # This comment belongs with the Background below it.',
    \ '    Background:',
    \ '        * def payload = 1',
    \ "        * def base = 'x'",
    \ '',
    \ '    @tagged',
    \ '    Scenario: a docstring keeps its own shape',
    \ '        Given path base',
    \ '        * eval',
    \ '        """',
    \ '        var doubled = payload * 2;',
    \ '          if (doubled > 2) {',
    \ '            doubled = 0;',
    \ '          }',
    \ '        """',
    \ '        Then match payload == 1',
    \ '',
    \ '    Scenario Outline: tables and examples',
    \ "        Given path '<id>'",
    \ '        Then match payload == 1',
    \ '        Examples:',
    \ '            | id |',
    \ '            | 1  |',
    \ ]

execute 'edit! ' . fnameescape(s:file)
doautocmd BufWinEnter
call s:Ok('fixture is clean, so formatting runs', get(b:, 'karate_has_errors', -1), 0)
call s:Ok('fixture starts out misindented', s:orig ==# s:want, v:false)

let s:raised = ''
try
    doautocmd BufWritePre
catch
    let s:raised = v:exception
endtry
call s:Ok('save raises nothing', s:raised, '')
call s:Ok('line count unchanged', line('$'), len(s:orig))

" Reported as the first offending line rather than as two 27-element lists.
let s:bad = []
for s:i in range(len(s:want))
    if getline(s:i + 1) !=# s:want[s:i]
        call add(s:bad, printf('L%d got |%s| want |%s|', s:i + 1, getline(s:i + 1), s:want[s:i]))
    endif
endfor
call s:Ok('every line indented as specified', s:bad, [])

" The payload invariant: Gherkin strips the opening delimiter's indentation
" from each body line, so moving the delimiter without the body would change
" the string Karate sends.
call s:Ok('docstring payload is byte-identical',
    \ s:Payload(getline(1, '$')), s:Payload(s:orig))

" --- 2. Formatting is idempotent, and a formatted file is not touched ---
call add(s:out, '--- idempotence')
let s:pass1 = getline(1, '$')
doautocmd BufWritePre
call s:Ok('a second save changes nothing', getline(1, '$'), s:pass1)

" Fixtures that are already correctly indented must come out untouched, and
" must not even be marked modified: gg=G rewrote all of these on every save.
for s:name in ['12_clean.feature', '31_autoformat_docstrings.feature',
    \ '05_docstring_ok.feature', '25_delimiters_ok.feature']
    let s:f = s:root . '/tests/fixtures/' . s:name
    let s:before = readfile(s:f)
    execute 'edit! ' . fnameescape(s:f)
    doautocmd BufWinEnter
    doautocmd BufWritePre
    call s:Ok(s:name . ': unchanged', getline(1, '$'), s:before)
    call s:Ok(s:name . ': not marked modified', &modified, 0)
endfor

" --- 3. Docstring bodies survive, block by block ---
" The restore loop used to abort on the first block it spliced and leave the
" rest of the file reindented and unrestored.
call add(s:out, '--- docstring bodies')
let s:file31 = s:root . '/tests/fixtures/31_autoformat_docstrings.feature'
let s:orig31 = readfile(s:file31)
let s:delims = s:Delims(s:orig31)
call s:Ok('fixture has several blocks', len(s:delims) >= 6, v:true)

execute 'edit! ' . fnameescape(s:file31)
doautocmd BufWinEnter
doautocmd BufWritePre

let s:k = 0
let s:intact = 0
let s:mangled = []
while s:k < len(s:delims) - 1
    let s:open = s:delims[s:k]
    let s:close = s:delims[s:k + 1]
    let s:body_want = s:open + 1 > s:close - 1 ? [] : s:orig31[s:open : s:close - 2]
    let s:body_got = s:open + 1 > s:close - 1 ? [] : getline(s:open + 1, s:close - 1)
    if s:body_want ==# s:body_got
        let s:intact += 1
    else
        call add(s:mangled, printf('block %d-%d: got %s', s:open, s:close, string(get(s:body_got, 0, ''))))
    endif
    let s:k += 2
endwhile
call s:Ok('every docstring body is verbatim', s:mangled, [])
call s:Ok('all blocks checked', s:intact, len(s:delims) / 2)

" --- 4. The fixup pass: saving fixes what the linter reports ---
" Tabs and trailing whitespace are both Error level, and any error blocks the
" indent pass -- so before this, the two things the formatter could fix were
" exactly the two that stopped it from running.
call add(s:out, '--- fixup pass')
enew! | file /tmp/karate_fixup.feature
call setline(1, ["Feature: f", '', 'Background:', "\t* def a = 1  ", '',
    \ 'Scenario: s', '  Given path a   '])
setlocal shiftwidth=4
doautocmd BufWinEnter
call s:Ok('tabs and trailing space are errors', get(b:, 'karate_has_errors', -1), 1)
doautocmd BufWritePre
call s:Ok('tab expanded and line reindented', getline(4), '        * def a = 1')
call s:Ok('trailing space stripped', getline(7), '        Given path a')
call s:Ok('no tabs left', search('\t', 'nw'), 0)
call s:Ok('no trailing whitespace left', search('\s\+$', 'nw'), 0)
doautocmd BufWinEnter
call s:Ok('the save left the file clean', len(KarateLinterReport()), 0)

" Trailing whitespace inside a docstring is payload: the rule does not report
" it, so the fix must not remove it.
enew! | file /tmp/karate_payload.feature
call setline(1, ['Feature: f', '', 'Background:', '* def a = 1', '', 'Scenario: s',
    \ 'Given path a', '* eval', '"""', 'keep me   ', '"""', 'Then match a == 1'])
doautocmd BufWinEnter
doautocmd BufWritePre
call s:Ok('docstring trailing space kept', getline(10), '        keep me   ')

" A rule that is switched off is not fixed either: turning the tabs rule off
" says tabs are acceptable in this project, so the tab hunt is not run.
" Leading whitespace is a separate matter -- the indent pass owns it and
" always writes spaces, which is what indent_width is counted in.
enew! | file /tmp/karate_tabsoff.feature
let g:karate_linter_tabs_rule = 0
call setline(1, ["Feature: f", '', 'Background:', "* def a = 'x\ty'", '',
    \ 'Scenario: s', "\tGiven path a"])
doautocmd BufWinEnter
doautocmd BufWritePre
call s:Ok('tabs rule off: mid-line tab left alone', getline(4), "        * def a = 'x\ty'")
call s:Ok('indentation is spaces regardless', getline(7), '        Given path a')
let g:karate_linter_tabs_rule = 1

" --- 4b. A tag or comment with nothing after it keeps the level it follows ---
" Seeding the backwards pass with 0 pulled these out to column 0 on every
" save: a note under the last step, and commented-out scenarios at the end of
" a file, are both common.
call add(s:out, '--- trailing tag and comment')
enew! | file /tmp/karate_trailing.feature
call setline(1, ['Feature: f', '', 'Background:', '* def a = 1', '',
    \ 'Scenario: s', 'Given path a', '# a note about the step above', '@orphan'])
doautocmd BufWinEnter
call s:Ok('trailing-run fixture is clean', get(b:, 'karate_has_errors', -1), 0)
doautocmd BufWritePre
call s:Ok('trailing comment keeps the step level', getline(8), '        # a note about the step above')
call s:Ok('dangling tag keeps it too', getline(9), '        @orphan')

" The other answer: a tag or comment that does have something after it still
" annotates that, which is what must not regress while fixing the above.
enew! | file /tmp/karate_leading.feature
call setline(1, ['@smoke', 'Feature: f', '', '# belongs with the Background',
    \ 'Background:', '* def a = 1', '', '@tagged', 'Scenario: s', 'Given path a'])
doautocmd BufWinEnter
doautocmd BufWritePre
call s:Ok('tag above Feature stays at 0', getline(1), '@smoke')
call s:Ok('comment takes the Background level', getline(4), '    # belongs with the Background')
call s:Ok('tag takes the Scenario level', getline(8), '    @tagged')

" --- 4c. A fence the engine cannot place stops the formatter dead ---
" Gherkin allows `'''` and a content type after `\"\"\"`; this engine's
" DOCSTRING_PATTERN matches neither, so it does not know where the docstrings
" are. `'''` linted clean and the indent pass moved the delimiter without its
" body -- the payload corruption invariant 4 exists to prevent.
call add(s:out, '--- unrecognised fences')
for [s:label, s:fence] in [['single-quoted', "'''"], ['typed', '"""json']]
    enew! | file /tmp/karate_fence.feature
    call setline(1, ['Feature: f', '', 'Background:', '* def a = 1', '',
        \ 'Scenario: s', '* def body =', s:fence, '  keep my shape  ', "\tand my tab",
        \ s:fence =~# "'" ? "'''" : '"""', 'Then match a == 1'])
    doautocmd BufWinEnter
    let s:before = getline(1, '$')
    " changedtick rather than &modified: the buffer was built with setline()
    " and so is already modified before the formatter is reached. This asserts
    " the stronger thing anyway -- that the save wrote nothing at all.
    let s:tick = b:changedtick
    doautocmd BufWritePre
    call s:Ok(s:label . ' fence: save changes nothing', getline(1, '$'), s:before)
    call s:Ok(s:label . ' fence: save wrote nothing at all', b:changedtick, s:tick)
    " Including the fixups: with the boundaries unknown, stripping a trailing
    " space or expanding a tab can just as easily eat part of a payload.
    call s:Ok(s:label . ' fence: payload tab kept', getline(10), "\tand my tab")
    let s:msg = execute('KarateFormat')
    call s:Ok(s:label . ' fence: KarateFormat says why', s:msg =~# 'bare """ fence', v:true)
    call s:Ok(s:label . ' fence: and touches nothing', getline(1, '$'), s:before)
endfor

" A `'''` inside a real docstring is payload, not a fence, so it must not
" switch the formatter off for the whole file.
enew! | file /tmp/karate_fence_ok.feature
call setline(1, ['Feature: f', '', 'Background:', '* def a = 1', '',
    \ 'Scenario: s', '* eval', '"""', "s = '''quoted'''", '"""', 'Then match a == 1'])
doautocmd BufWinEnter
doautocmd BufWritePre
call s:Ok('quotes inside a docstring still format', getline(7), '        * eval')
call s:Ok('and that body line is untouched', getline(9), "        s = '''quoted'''")

" --- 5. An error the formatter cannot fix still blocks the indent pass ---
call add(s:out, '--- error gate')
enew! | file /tmp/karate_bad.feature
call setline(1, ['Feature: f', '', 'Background:', '* def a = read(', '',
    \ 'Scenario: s', 'Given path a'])
doautocmd BufWinEnter
let s:before = getline(1, '$')
doautocmd BufWritePre
call s:Ok('unclosed read(): not reindented', getline(1, '$'), s:before)
call s:Ok('error cache still set', get(b:, 'karate_has_errors', -1), 1)

" --- 6. :KarateFormat ---
call add(s:out, '--- KarateFormat')
execute 'edit! ' . fnameescape(s:file)
doautocmd BufWinEnter
let s:msg = execute('KarateFormat')
call s:Ok('reindents the buffer', getline(1, '$'), s:want)
call s:Ok('reports what it did', s:msg =~# 'reindented', v:true)
let s:msg = execute('KarateFormat')
call s:Ok('nothing left to do the second time', s:msg =~# '0 line(s) reindented', v:true)

" On a file with errors it refuses, and says so -- an unclosed docstring makes
" the block boundaries wrong, and indenting a payload line as a step would
" rewrite what Karate sends.
execute 'edit! ' . fnameescape(s:root . '/tests/fixtures/04_docstring_unclosed.feature')
doautocmd BufWinEnter
let s:before = getline(1, '$')
let s:msg = execute('KarateFormat')
call s:Ok('refuses while the file has errors', s:msg =~# 'not reindenting', v:true)
call s:Ok('and leaves the buffer alone', getline(1, '$'), s:before)

" --- 7. karate_linter_indent_width ---
call add(s:out, '--- indent width')
let g:karate_linter_indent_width = 2
enew! | file /tmp/karate_width.feature
call setline(1, ['Feature: f', '', 'Background:', '* def a = 1', '',
    \ 'Scenario Outline: s', "Given path '<h>'", 'Then match a == 1',
    \ 'Examples:', '| h |', '| 1 |'])
doautocmd BufWinEnter
call s:Ok('width fixture is clean', get(b:, 'karate_has_errors', -1), 0)
doautocmd BufWritePre
call s:Ok('width 2: scenario level', getline(6), '  Scenario Outline: s')
call s:Ok('width 2: step level', getline(7), "    Given path '<h>'")
call s:Ok('width 2: examples level', getline(9), '    Examples:')
call s:Ok('width 2: table level', getline(10), '      | h |')
let g:karate_linter_indent_width = 4

" --- 8. :KarateTabsToSpaces replaces tabs ---
" It was a silent no-op: the E1050 was swallowed by silent! and the command
" still echoed that it had replaced them.
call add(s:out, '--- KarateTabsToSpaces')
enew!
setlocal shiftwidth=4 noexpandtab
call setline(1, ["\tGiven one tab", "\t\tGiven two tabs", 'Given none'])
KarateTabsToSpaces
call s:Ok('leading tab replaced', getline(1), '    Given one tab')
call s:Ok('both tabs replaced', getline(2), '        Given two tabs')
call s:Ok('tab-free line untouched', getline(3), 'Given none')
call s:Ok('no tabs left in the buffer', search('\t', 'nw'), 0)

" A tab in the middle of a line is replaced too, and the cursor stays put.
enew!
setlocal shiftwidth=4
call setline(1, ['Given path', "* def a = 'x\ty'"])
call cursor(2, 3)
KarateTabsToSpaces
call s:Ok('mid-line tab replaced', getline(2), "* def a = 'x    y'")
call s:Ok('cursor not moved', [line('.'), col('.')], [2, 3])

" A file with no tabs at all must not be an error.
enew!
call setline(1, ['Given nothing to do'])
let s:raised = ''
try
    KarateTabsToSpaces
catch
    let s:raised = v:exception
endtry
call s:Ok('no tabs: raises nothing', s:raised, '')

" --- 9. :KarateFmtJson rewrites the block it is in ---
call add(s:out, '--- KarateFmtJson')
if !executable('jq') && !executable('python3') && !executable('python')
    call add(s:out, '  skip no jq or python available')
else
    execute 'edit! ' . fnameescape(s:file31)
    " Into the JSON block: find the line holding its opening brace.
    let s:brace = search('^\s*{\s*$', 'w')
    call s:Ok('found the json block', s:brace > 0, v:true)
    call cursor(s:brace, 1)
    let s:raised = ''
    try
        KarateFmtJson
    catch
        let s:raised = v:exception
    endtry
    call s:Ok('formatting raises nothing', s:raised, '')
    call s:Ok('block was reindented', getline(s:brace + 1) =~# '^\s\+"a"', v:true)
    call s:Ok('next save is skipped once', get(b:, 'karate_just_formatted_json', 0), 1)

    " That flag must actually suppress the save-time reformat, or the JSON
    " indentation just applied would be handed straight back to the formatter.
    let s:json = getline(s:brace, s:brace + 6)
    doautocmd BufWritePre
    call s:Ok('save left the new json alone', getline(s:brace, s:brace + 6), s:json)
    call s:Ok('flag cleared after one save', get(b:, 'karate_just_formatted_json', -1), 0)

    " A block that is not JSON is refused, not mangled.
    execute 'edit! ' . fnameescape(s:file31)
    call cursor(search('for (var i', 'w'), 1)
    let s:before = getline(1, '$')
    let s:msg = execute('KarateFmtJson')
    call s:Ok('non-json block refused', s:msg =~# 'does not look like', v:true)
    call s:Ok('non-json block untouched', getline(1, '$'), s:before)
endif

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/format.txt')
qa!

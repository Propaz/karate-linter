" Checks the cursor-line message: which diagnostic wins, how it is formatted,
" truncation, and that the command line is not written to needlessly.
"
"   vim -Nu NONE -es -S tests/check_echo.vim

set nocompatible noignorecase nomore noswapfile
set encoding=utf-8
set columns=80 noshowcmd

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
        call add(s:out, printf('  ok   %-44s %s', a:label, string(a:got)))
    else
        let s:fail += 1
        call add(s:out, printf('  FAIL %-44s\n         got  %s\n         want %s',
            \ a:label, string(a:got), string(a:want)))
    endif
endfunction

" What the plugin would print, captured through the real autocmd.
function! s:EchoAt(lnum, col) abort
    call cursor(a:lnum, a:col)
    return substitute(execute('doautocmd CursorMoved'), '^[\r\n]*', '', '')
endfunction

function! s:Fixture(name) abort
    execute 'edit! ' . fnameescape(s:root . '/tests/fixtures/' . a:name)
    unlet! b:karate_echoed
endfunction

" --- 1. A line with a single diagnostic ---
call add(s:out, '--- single diagnostic')
call s:Fixture('14_parens_bad.feature')
call s:Ok('unclosed paren message', s:EchoAt(7, 1),
    \ "[karate] E: Unclosed '(' in call to 'read'")

" --- 2. A line with two diagnostics: error wins, count is shown ---
" L11 is "* def v = myJsHelper(base": an unused-variable warning at col 15 and
" an unclosed-paren error at col 19.
call add(s:out, '--- two diagnostics on one line')
call s:Fixture('14_parens_bad.feature')
call s:Ok('error preferred over warning', s:EchoAt(11, 1),
    \ "[karate] E: Unclosed '(' in call to 'myJsHelper'  (+1 more)")
call s:Fixture('14_parens_bad.feature')
call s:Ok('cursor inside the warning range wins', s:EchoAt(11, 15),
    \ '[karate] W: Unused variable: v  (+1 more)')

" --- 3. A clean line clears the message ---
call add(s:out, '--- clearing')
call s:Fixture('14_parens_bad.feature')
call s:Ok('diagnostic shown first', s:EchoAt(7, 1) !=# '', v:true)
call s:Ok('moving to a clean line clears', s:EchoAt(5, 1), '')
call s:Ok('staying on a clean line is a no-op', s:EchoAt(4, 1), '')

" --- 4. Long messages must not fill the command line ---
call add(s:out, '--- truncation (columns=80)')
call s:Fixture('06_placeholders.feature')
let s:msg = s:EchoAt(11, 23)
call s:Ok('long message is clipped', strdisplaywidth(s:msg) <= 79, v:true)
call s:Ok('clipped with ellipsis', s:msg =~# '\.\.\.$', v:true)
call s:Ok('prefix survives clipping', s:msg =~# '^\[karate\] W: ', v:true)

" --- 5. Truncation counts display cells, not bytes ---
" The cut lands inside a long Cyrillic placeholder name. Truncating by bytes
" (what printf('%.<n>S') does) would stop at roughly half the width, so a
" message that nearly fills the line proves cells are being counted.
call add(s:out, '--- multibyte truncation')
call s:Fixture('22_long_multibyte_message.feature')
let s:msg = s:EchoAt(7, 21)
let s:w = strdisplaywidth(s:msg)
call s:Ok('message fits the command line', s:w <= 79, v:true)
call s:Ok('message uses the width available', s:w >= 70, v:true)
call s:Ok('cut lands inside the cyrillic name', s:msg =~# '[а-яА-Я]\.\.\.', v:true)
call s:Ok('the (+N more) suffix is kept whole', s:msg =~# '(+1 more)$', v:true)

" --- 6. Opening a file must not add a message of its own ---
" Regression: echoing from the buffer-load autocmd landed on top of Vim's own
" ':edit' message, which forces a 'Press ENTER' prompt. It also reported the
" wrong line, because the cursor had not been placed yet.
call add(s:out, '--- silent on open')
function! s:OpenNoise(name) abort
    enew!
    let raw = execute('edit! ' . fnameescape(s:root . '/tests/fixtures/' . a:name))
    " Everything except Vim's own "file" NL, NB line.
    return join(filter(split(raw, '\n'), 'v:val !~# "^\"" && v:val !~# "^$"'), '|')
endfunction
call s:Ok('open with diagnostic at eof is silent', s:OpenNoise('14_parens_bad.feature'), '')
call s:Ok('open with diagnostic on line 1 is silent', s:OpenNoise('09_structure_missing_all.feature'), '')
call s:Ok('open of a clean file is silent', s:OpenNoise('12_clean.feature'), '')

" --- 7. An edit on the cursor line refreshes via the debounce timer ---
" No CursorMoved happens when the text under a stationary cursor changes, so
" the timer is what keeps the message honest.
call add(s:out, '--- refresh after edit')
call s:Fixture('12_clean.feature')
call cursor(7, 1)
call s:Ok('clean line, nothing echoed', get(b:, 'karate_echoed', '<unset>'), '<unset>')
call setline(7, getline(7) . '   ')
doautocmd TextChanged
sleep 400m
call s:Ok('timer picked up the new diagnostic',
    \ get(b:, 'karate_echoed', ''), '[karate] E: Trailing whitespace')
call setline(7, substitute(getline(7), '\s\+$', '', ''))
doautocmd TextChanged
sleep 400m
call s:Ok('timer cleared it again', get(b:, 'karate_echoed', '<unset>'), '')

" --- 8. The toggle switches it off ---
call add(s:out, '--- option')
let g:karate_linter_echo_cursor = 0
call s:Fixture('14_parens_bad.feature')
call s:Ok('echo_cursor=0 stays silent', s:EchoAt(7, 1), '')
let g:karate_linter_echo_cursor = 1

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/echo.txt')
qa!

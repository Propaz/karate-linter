" Checks :KarateLintCheck as a navigation aid: the order of the list, that its
" entries actually jump, and that a stale list is not left behind.
"
"   vim -Nu NONE -es -S tests/check_loclist.vim

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

function! s:Fixture(name) abort
    lclose
    execute 'edit! ' . fnameescape(s:root . '/tests/fixtures/' . a:name)
endfunction

" --- 1. The list is ordered by position, not by rule ---
" The report is built rule by rule; unsorted, the list for fixture 14 starts
" 8, 9, 11, 7, which makes :lnext walk backwards through the file.
call add(s:out, '--- ordering')
call s:Fixture('14_parens_bad.feature')
call cursor(1, 1)
KarateLintCheck
let s:items = getloclist(0)
call s:Ok('list is not empty', len(s:items) > 0, v:true)
let s:sorted = v:true
for s:i in range(1, len(s:items) - 1)
    let s:p = s:items[s:i - 1]
    let s:c = s:items[s:i]
    if s:c.lnum < s:p.lnum || (s:c.lnum == s:p.lnum && s:c.col < s:p.col)
        let s:sorted = v:false
    endif
endfor
call s:Ok('entries ascend by line then column', s:sorted, v:true)
call s:Ok('first entry is the first issue in the file', s:items[0].lnum, 7)

" --- 2. Entries reference the buffer, so they jump ---
call add(s:out, '--- jumping')
call s:Ok('entry carries a buffer number', s:items[0].bufnr > 0, v:true)
call s:Ok('entry is valid', s:items[0].valid, 1)
ll 1
call s:Ok('ll 1 lands on the reported line', line('.'), s:items[0].lnum)
call s:Ok('ll 1 lands on the reported column', col('.'), s:items[0].col)
lclose

" --- 3. An unnamed buffer jumps too ---
" Entries used to carry a filename; for a buffer with no name that resolved to
" nothing and the jump silently did nothing at all.
call add(s:out, '--- unnamed buffer')
enew!
call setline(1, ['Feature: f', '', 'Scenario: s', '  * def a = read(x', '  * print a'])
KarateLintCheck
let s:un = getloclist(0)
" Jump to the read() on line 4 specifically: structure warnings sit on line 1,
" where the cursor already is, so jumping to the first entry proves nothing.
let s:target = 0
for s:i in range(len(s:un))
    if s:un[s:i].lnum == 4
        let s:target = s:i + 1
        break
    endif
endfor
call s:Ok('unnamed buffer reports the read() line', s:target > 0, v:true)
call s:Ok('entry carries a real buffer number', s:un[s:target - 1].bufnr > 0, v:true)
call cursor(1, 1)
execute 'll ' . s:target
call s:Ok('jump moves the cursor', line('.'), 4)
lclose

" --- 4. The list opens on the entry you were looking at ---
call add(s:out, '--- selected entry')
call s:Fixture('14_parens_bad.feature')
call cursor(11, 1)
KarateLintCheck
" :lopen puts the cursor on the list's current entry.
let s:sel = getloclist(0)[line('.') - 1]
call s:Ok('cursor sits on an entry for the cursor line', s:sel.lnum, 11)
lclose

call s:Fixture('14_parens_bad.feature')
call cursor(1, 1)
KarateLintCheck
call s:Ok('from the top of the file, the first entry', line('.'), 1)
lclose

" --- 5. A clean file does not leave the old list behind ---
" Stale entries still jump, and after a fix they land on the wrong lines.
call add(s:out, '--- clean file')
call s:Fixture('14_parens_bad.feature')
KarateLintCheck
call s:Ok('list populated before', len(getloclist(0)) > 0, v:true)
call s:Fixture('12_clean.feature')
let s:msg = execute('KarateLintCheck')
call s:Ok('reports no issues', s:msg =~# 'No issues found', v:true)
call s:Ok('old entries are gone', len(getloclist(0)), 0)
call s:Ok('no location window is left open', &buftype, '')

" --- 6. Running the command from the list window does not lint the list ---
call add(s:out, '--- guard')
call s:Fixture('14_parens_bad.feature')
KarateLintCheck
call s:Ok('focus is in the location window', &buftype, 'quickfix')
let s:before = getloclist(0)
let s:msg = execute('KarateLintCheck')
call s:Ok('refuses politely', s:msg =~# 'needs a file buffer', v:true)
call s:Ok('list is left alone', getloclist(0) ==# s:before, v:true)
lclose

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/loclist.txt')
qa!

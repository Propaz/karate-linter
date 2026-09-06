" Dumps the raw linter report for every fixture, in a stable text format.
"
" Usage:
"   vim -Nu NONE -es -S tests/dump_report.vim
"   KL_OUT=after.txt vim -Nu NONE -es -S tests/dump_report.vim
"
" The output is meant to be diffed between refactors: any change in the diff
" is a change in what the linter reports.

set nocompatible
set noignorecase
set nomore
set shortmess+=A
set noswapfile
set encoding=utf-8

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
" The engine is loaded lazily from autoload/, so the repo has to be on
" the runtimepath before the plugin file is sourced.
let s:rtp = substitute(s:root, '\', '/', 'g')
execute 'set runtimepath^=' . escape(s:rtp, ' ,')
execute 'source ' . fnameescape(s:root . '/plugin/karate_linter.vim')

" Formats one issue into a stable single line.
function! s:Fmt(issue) abort
    return printf('    L%-3d c%-3d-%-3d %-16s %s',
        \ a:issue.lnum, a:issue.col, a:issue.end_col,
        \ substitute(a:issue.level, '^KarateLint', '', ''), a:issue.text)
endfunction

let s:out = []
let s:sorted_out = []
let s:fixtures = sort(glob(s:root . '/tests/fixtures/*.feature', 0, 1))

if empty(s:fixtures)
    call writefile(['FATAL: no fixtures found'], s:root . '/tests/FATAL.txt')
    qa!
endif

for s:f in s:fixtures
    execute 'edit! ' . fnameescape(s:f)
    call add(s:out, '=== ' . fnamemodify(s:f, ':t'))

    let s:report = []
    try
        let s:report = KarateLinterReport()
    catch
        call add(s:out, '    EXCEPTION: ' . v:exception)
    endtry

    call add(s:sorted_out, '=== ' . fnamemodify(s:f, ':t'))
    if empty(s:report)
        call add(s:out, '    (no issues)')
        call add(s:sorted_out, '    (no issues)')
    endif

    " Raw order: the order the report is built in, which drives loclist order.
    for s:issue in s:report
        call add(s:out, s:Fmt(s:issue))
    endfor

    " Sorted order: the SET of diagnostics, independent of build order.
    " Dictionary iteration (unused variables) has no guaranteed order, so this
    " is the section to compare strictly across refactors.
    for s:line in sort(map(copy(s:report), {_, i -> s:Fmt(i)}))
        call add(s:sorted_out, s:line)
    endfor
endfor

let s:suffix = empty($KL_OUT) ? 'baseline' : $KL_OUT
call writefile(s:out, s:root . '/tests/' . s:suffix . '.raw.txt')
call writefile(s:sorted_out, s:root . '/tests/' . s:suffix . '.sorted.txt')
qa!

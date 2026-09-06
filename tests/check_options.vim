" Checks one option scenario per Vim invocation (the plugin's load guard means
" globals have to be set with --cmd, before it is sourced).
"
" Driven by tests/run.sh:
"   KL_FIXTURE  fixture to lint          (default 14_parens_bad.feature)
"   KL_MATCH    pattern selecting the diagnostics of interest
"   KL_RESULT   file to write "<count> <level>" into

set nocompatible noignorecase nomore noswapfile
set encoding=utf-8

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
execute 'source ' . fnameescape(s:root . '/plugin/karate_linter.vim')

let s:fixture = empty($KL_FIXTURE) ? '14_parens_bad.feature' : $KL_FIXTURE
let s:match = empty($KL_MATCH) ? "Unclosed '('" : $KL_MATCH
execute 'edit! ' . fnameescape(s:root . '/tests/fixtures/' . s:fixture)

let s:n = 0
let s:level = '-'
for s:issue in KarateLinterReport()
    if s:issue.text =~# s:match
        let s:n += 1
        let s:level = s:issue.level
    endif
endfor

call writefile([s:n . ' ' . s:level], $KL_RESULT)
qa!

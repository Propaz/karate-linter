" Checks the formatting paths: auto-format on save, :KarateFmtJson and
" :KarateTabsToSpaces.
"
" None of this had coverage before, and all three were broken by the Vim9
" port: a range inside an :execute string needs a leading colon, and without
" one Vim throws E1050. The first two crashed out of the autocommand; the
" third was wrapped in silent! and reported success while doing nothing.
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

" Line numbers of the """ delimiters, from the file on disk.
function! s:Delims(lines) abort
    let l:d = []
    for l:i in range(len(a:lines))
        if a:lines[l:i] =~# '^\s*"""\s*$'
            call add(l:d, l:i + 1)
        endif
    endfor
    return l:d
endfunction

" --- 1. Auto-format on save leaves docstring bodies alone ---
call add(s:out, '--- auto-format on save')
let s:file = s:root . '/tests/fixtures/31_autoformat_docstrings.feature'
let s:orig = readfile(s:file)
let s:delims = s:Delims(s:orig)
call s:Ok('fixture has several blocks', len(s:delims) >= 6, v:true)

execute 'edit! ' . fnameescape(s:file)
doautocmd BufWinEnter
call s:Ok('fixture is clean, so formatting runs', get(b:, 'karate_has_errors', -1), 0)

let s:raised = ''
try
    doautocmd BufWritePre
catch
    let s:raised = v:exception
endtry
call s:Ok('save raises nothing', s:raised, '')
call s:Ok('line count unchanged', line('$'), len(s:orig))

" Every block, not just the first: the restore loop used to abort partway and
" leave the remaining blocks with gg=G's indentation.
let s:k = 0
let s:intact = 0
let s:mangled = []
while s:k < len(s:delims) - 1
    let s:open = s:delims[s:k]
    let s:close = s:delims[s:k + 1]
    let s:want = s:open + 1 > s:close - 1 ? [] : s:orig[s:open : s:close - 2]
    let s:got = s:open + 1 > s:close - 1 ? [] : getline(s:open + 1, s:close - 1)
    if s:want ==# s:got
        let s:intact += 1
    else
        call add(s:mangled, printf('block %d-%d: got %s', s:open, s:close, string(get(s:got, 0, ''))))
    endif
    let s:k += 2
endwhile
call s:Ok('every docstring body is verbatim', s:mangled, [])
call s:Ok('all blocks checked', s:intact, len(s:delims) / 2)

" The file outside the blocks must actually have been formatted, or the check
" above would pass just as well on a no-op.
let s:in_block = 0
let s:changed_outside = 0
for s:i in range(len(s:orig))
    if s:orig[s:i] =~# '^\s*"""\s*$'
        let s:in_block = !s:in_block
        continue
    endif
    if !s:in_block && getline(s:i + 1) !=# s:orig[s:i]
        let s:changed_outside += 1
    endif
endfor
call s:Ok('lines outside blocks were formatted', s:changed_outside > 0, v:true)

" --- 2. :KarateTabsToSpaces replaces tabs ---
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

" --- 3. :KarateFmtJson rewrites the block it is in ---
call add(s:out, '--- KarateFmtJson')
if !executable('jq') && !executable('python3') && !executable('python')
    call add(s:out, '  skip no jq or python available')
else
    execute 'edit! ' . fnameescape(s:file)
    " Into the JSON block: find the line holding its opening brace.
    let s:brace = search('^\s*{\s*$', 'w')
    call s:Ok('found the json block', s:brace > 0, v:true)
    call cursor(s:brace, 1)
    let s:before = line('$')
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
    " indentation just applied would be handed straight back to gg=G.
    let s:json = getline(s:brace, s:brace + 6)
    doautocmd BufWritePre
    call s:Ok('save left the new json alone', getline(s:brace, s:brace + 6), s:json)
    call s:Ok('flag cleared after one save', get(b:, 'karate_just_formatted_json', -1), 0)
endif

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/format.txt')
qa!

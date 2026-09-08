" The fresh-install path, which no other check covers.
"
" Every other check_*.vim runs with `-Nu NONE` and sources plugin/ by hand.
" That is not how a user gets the plugin: Vim loads it itself, after a vimrc
" has put the repository on the runtimepath. This script is driven that way
" instead - tests/run.sh writes a vimrc containing nothing but that one line -
" so the thing under test is Vim's own plugin loading, then a second source of
" the same file, which is what a plugin manager's update hook does.
"
"   printf 'set runtimepath^=%s\n' "$PWD" > /tmp/klvimrc
"   vim -Nu /tmp/klvimrc -es -S tests/check_install.vim
"
" Note there is no `filetype on` in that vimrc, so detection is off and
" &filetype is empty. The plugin hooks the file *pattern*, so it must work
" anyway - that is what the diagnostics assertions below are for.

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:probe = s:root . '/tests/fixtures/01_simple_rules.feature'
let s:out = []
let s:fail = 0

function! s:Ok(label, got, want) abort
    if a:got ==# a:want
        call add(s:out, printf('  ok   %-44s %s', a:label, string(a:got)))
    else
        let s:fail += 1
        call add(s:out, printf('  FAIL %-44s got=%s want=%s',
            \ a:label, string(a:got), string(a:want)))
    endif
endfunction

" --- 1. Vim loaded the plugin on its own ---
call add(s:out, '--- loaded by vim, not by hand')
execute 'edit! ' . fnameescape(s:probe)
call s:Ok('filetype detection is off, as that vimrc implies', &filetype, '')
for s:cmd in ['KarateLintCheck', 'KarateFormat', 'KarateFmtJson',
    \ 'KarateAlignDocstring', 'KarateTabsToSpaces']
    call s:Ok(s:cmd . ' defined', exists(':' . s:cmd), 2)
endfor
call s:Ok('KarateLinterReport() available', exists('*KarateLinterReport'), 1)

" --- 2. The three things a user sees ---
call add(s:out, '--- diagnostics, gutter, message')
let s:report = KarateLinterReport()
call s:Ok('diagnostics found', len(s:report) > 0, v:true)

let s:props = 0
for s:lnum in range(1, line('$'))
    let s:props += len(prop_list(s:lnum))
endfor
call s:Ok('text properties placed', s:props > 0, v:true)

let s:placed = sign_getplaced(bufnr('%'), {'group': 'karate_linter_' . bufnr('%')})
call s:Ok('signs placed', !empty(s:placed) && len(s:placed[0].signs) > 0, v:true)

if len(s:report) > 0
    call cursor(s:report[0].lnum, s:report[0].col)
    call s:Ok('cursor message appears, [karate] lowercase',
        \ execute('doautocmd CursorMoved') =~# '\[karate\]', v:true)
endif

" --- 3. Sourced a second time, the way a manager updates it ---
" This is the path that broke for three releases: a Vim9 script's
" script-local items are cleared before a re-source and the load guard then
" returns before the `import autoload` can come back, leaving the surviving
" autocommands to fail with E121 on every keystroke. `vim9script noclear`.
call add(s:out, '--- after a second source')
execute 'source ' . fnameescape(s:root . '/plugin/karate_linter.vim')

let s:raised = ''
let s:again = -1
try
    execute 'edit! ' . fnameescape(s:probe)
    doautocmd BufWinEnter
    doautocmd CursorMoved
    let s:again = len(KarateLinterReport())
catch
    let s:raised = v:exception
endtry
call s:Ok('no exception out of the autocommands', s:raised, '')
call s:Ok('same diagnostics as before', s:again, len(s:report))
call s:Ok('commands still resolve', exists(':KarateFormat'), 2)

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/install.txt')
qa!

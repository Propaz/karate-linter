" Checks that the plugin survives being sourced a second time in a running
" Vim -- `:source $MYVIMRC` after editing it, or a plugin manager's update
" hook.
"
" This is not a hypothetical. Sourcing a Vim9 script again clears its
" script-local items *before* executing it, and the `exists()` load guard then
" returns before the `import autoload` can be re-created. The autocommands and
" commands registered by the first load survive that and still resolve against
" this script's now-empty context, so every one of them failed with
"
"   E121: Undefined variable: linter
"
" until Vim was restarted -- on CursorMoved, which is to say on every
" keystroke. `vim9script noclear` is the fix, and this file is what pins it
" down.
"
" Everything is driven through the real autocommands and commands, never a
" script-local function: the wiring is precisely what broke.
"
"   vim -Nu NONE -es -S tests/check_reload.vim

set nocompatible noignorecase nomore noswapfile
set encoding=utf-8

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:rtp = substitute(s:root, '\', '/', 'g')
execute 'set runtimepath^=' . escape(s:rtp, ' ,')
let s:plugin = s:root . '/plugin/karate_linter.vim'
let s:fixture = s:root . '/tests/fixtures/01_simple_rules.feature'

execute 'source ' . fnameescape(s:plugin)

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

" The exception text, or '' -- which is what every assertion here wants.
function! s:Caught(cmd) abort
    try
        execute a:cmd
    catch
        return v:exception
    endtry
    return ''
endfunction

call add(s:out, '--- before the re-source')

execute 'edit! ' . fnameescape(s:fixture)
doautocmd BufWinEnter
call s:Ok('fixture lints on load', len(KarateLinterReport()), 8)

" ---------------------------------------------------------------------------
" Re-sourcing the plugin. Three times, because the failure is about state
" that the *second* load destroys and a third would be the first to see a
" half-initialised script if `noclear` were only papering over it.
"
" A colorscheme in between, because a vimrc that gets re-sourced almost always
" sets one, and `:colorscheme` runs `:highlight clear`.

for s:n in [1, 2, 3]
    " From disk, because :KarateTabsToSpaces below edits the buffer and the
    " finding count has to mean the same thing on every iteration. Nothing
    " here ever writes, so the fixture on disk is untouched.
    execute 'edit! ' . fnameescape(s:fixture)

    colorscheme default
    execute 'source ' . fnameescape(s:plugin)
    let s:tag = printf('re-source #%d: ', s:n)

    " Every autocommand in the augroup, in the order a user would hit them.
    call s:Ok(s:tag .. 'BufWinEnter', s:Caught('doautocmd BufWinEnter'), '')
    call s:Ok(s:tag .. 'BufReadPost', s:Caught('doautocmd BufReadPost'), '')
    call s:Ok(s:tag .. 'CursorMoved', s:Caught('doautocmd CursorMoved'), '')
    call s:Ok(s:tag .. 'TextChanged', s:Caught('doautocmd TextChanged'), '')

    " The diagnostics are still real, not merely error-free.
    call s:Ok(s:tag .. 'report still populated', len(KarateLinterReport()), 8)

    " BufWritePre last of the events: the fixup pass runs ahead of the error
    " gate, so it removes the tab and the trailing space even though the file
    " is too broken to reindent. Two findings fewer is this file working, not
    " a re-source casualty.
    call s:Ok(s:tag .. 'BufWritePre', s:Caught('doautocmd BufWritePre'), '')
    call s:Ok(s:tag .. 'fixup pass ran', len(KarateLinterReport()), 6)

    " `highlight default link` is restored by the `:highlight clear` inside
    " `:colorscheme`, so the links established at the first load survive and
    " the plugin needs no ColorScheme autocommand. Asserted rather than
    " assumed -- the opposite was the expectation.
    call s:Ok(s:tag .. 'KarateLintError link',
        \ get(hlget('KarateLintError')[0], 'linksto', '<none>'), 'Error')
    call s:Ok(s:tag .. 'KarateLintWarn link',
        \ get(hlget('KarateLintWarn')[0], 'linksto', '<none>'), 'Todo')

    " And every command.
    call s:Ok(s:tag .. ':KarateLintCheck', s:Caught('KarateLintCheck'), '')
    lclose
    call s:Ok(s:tag .. ':KarateFormat', s:Caught('KarateFormat'), '')
    call s:Ok(s:tag .. ':KarateFmtJson', s:Caught('KarateFmtJson'), '')
    call s:Ok(s:tag .. ':KarateAlignDocstring', s:Caught('KarateAlignDocstring'), '')
    call s:Ok(s:tag .. ':KarateTabsToSpaces', s:Caught('KarateTabsToSpaces'), '')
endfor

" ---------------------------------------------------------------------------
" The other order: re-source while no .feature buffer exists, so the engine
" has not been imported at that point either, and only then open a file.

call add(s:out, '--- re-source with no .feature buffer open')

enew!
execute 'source ' . fnameescape(s:plugin)
execute 'edit! ' . fnameescape(s:fixture)
call s:Ok('BufWinEnter after cold re-source', s:Caught('doautocmd BufWinEnter'), '')
call s:Ok('report after cold re-source', len(KarateLinterReport()), 8)

" ---------------------------------------------------------------------------
" The guard itself still does its job: a second load must not re-run the
" configuration, or a user's own setting would be overwritten by the default.

call add(s:out, '--- the load guard still guards')

let g:karate_linter_max_line_length = 42
execute 'source ' . fnameescape(s:plugin)
call s:Ok('user option survives the re-source', g:karate_linter_max_line_length, 42)
let g:karate_linter_max_line_length = 120

call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILED', s:fail))
call writefile(s:out, s:root . '/tests/reload.txt')
qall!

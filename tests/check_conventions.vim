" Checks the repository's conventions about itself, not the linter's output.
"
" The other check_*.vim scripts assert what the linter reports. This one
" asserts the things an audit finds and a suite normally cannot: an option
" nobody documented, a rule whose off-switch is never executed, a function
" renamed out from under a document, a fixture the baseline has never seen.
" Every one of these has actually rotted here at least once.
"
" All four checks are textual on purpose - they read the sources as text
" rather than importing them, because what they are testing is whether two
" files still agree, and a checker that resolves symbols would hide exactly
" the drift it is looking for.
"
"   vim -Nu NONE -es -S tests/check_conventions.vim

set nocompatible
set noignorecase
set nomore
set noswapfile
set encoding=utf-8

let s:root = fnamemodify(expand('<sfile>:p'), ':h:h')
let s:out = []
let s:fail = 0

function! s:Ok(label, got, want) abort
    if a:got ==# a:want
        call add(s:out, printf('  ok   %-46s %s', a:label, string(a:got)))
    else
        let s:fail += 1
        call add(s:out, printf('  FAIL %-46s got=%s want=%s',
            \ a:label, string(a:got), string(a:want)))
    endif
endfunction

function! s:Read(rel) abort
    let l:path = s:root . '/' . a:rel
    return filereadable(l:path) ? readfile(l:path) : []
endfunction

function! s:Text(rel) abort
    return join(s:Read(a:rel), "\n")
endfunction

" Every token the docs put in backticks. Splitting on the backtick with
" keepempty keeps the indices stable, so the odd ones are the code spans.
" A line with an unbalanced backtick flips that, which at worst offers a
" non-identifier for inspection - the checks below all ignore what they
" cannot recognise.
function! s:Backticked(rel) abort
    let l:spans = []
    for l:line in s:Read(a:rel)
        let l:parts = split(l:line, '`', 1)
        let l:i = 1
        while l:i < len(l:parts)
            call add(l:spans, l:parts[l:i])
            let l:i += 2
        endwhile
    endfor
    return l:spans
endfunction

let s:docs = ['CLAUDE.md', 'docs/claude/playbooks.md']

" --- 1. Every rule's `_rule = 0` path is executed, or is declared as debt ---
" The `option handling` section of tests/run.sh is the only place a rule's off
" switch runs. The convention (CLAUDE.md; playbooks, *Adding a rule* step 6)
" arrived after most of the rules did and was never applied backwards, so the
" rules that predate it are named here instead of papered over. The list is a
" ratchet: a new rule may not join it, and a rule that gains a toggle case
" must leave it.
call add(s:out, '--- rule toggle coverage')

let s:untoggled_debt = [
    \ 'and_but',
    \ 'call_read_space',
    \ 'missing_background',
    \ 'missing_examples',
    \ 'missing_feature',
    \ 'missing_scenario',
    \ 'no_space_after_keyword',
    \ 'orphaned_examples',
    \ 'tabs',
    \ 'trailing_space',
    \ 'unclosed_docstring',
    \ 'undefined_placeholder',
    \ 'undefined_request_var',
    \ 'unused_header',
    \ 'unused_variable',
    \ ]

" The rule names, taken from the DEFAULTS block itself.
let s:in_defaults = 0
let s:rules = []
let s:options = []
for s:line in s:Read('plugin/karate_linter.vim')
    if s:line =~# '^const DEFAULTS = {'
        let s:in_defaults = 1
        continue
    endif
    if s:in_defaults && s:line =~# '^}'
        let s:in_defaults = 0
        continue
    endif
    if !s:in_defaults
        continue
    endif
    let s:key = matchstr(s:line, '^\s*\zskarate_linter_\w\+\ze\s*:')
    if empty(s:key)
        continue
    endif
    call add(s:options, s:key)
    let s:rule = matchstr(s:key, '^karate_linter_\zs\w\+\ze_rule$')
    if !empty(s:rule)
        call add(s:rules, s:rule)
    endif
endfor
call s:Ok('DEFAULTS parsed at all', len(s:rules) > 10, v:true)

let s:runsh = s:Text('tests/run.sh')
let s:toggled = filter(copy(s:rules),
    \ 's:runsh =~# ''karate_linter_'' . v:val . ''_rule = 0''')
let s:untested = filter(copy(s:rules), 'index(s:toggled, v:val) == -1')

call s:Ok('no new rule without an off-switch test',
    \ filter(copy(s:untested), 'index(s:untoggled_debt, v:val) == -1'), [])
call s:Ok('no stale entry in the toggle debt list',
    \ filter(copy(s:untoggled_debt), 'index(s:toggled, v:val) >= 0'), [])
call s:Ok('every debt entry is a real rule',
    \ filter(copy(s:untoggled_debt), 'index(s:rules, v:val) == -1'), [])

" --- 2. Every option is documented, and the README invents none ---
" Step 7 of *Adding a rule*. Both directions matter: an undocumented option is
" unusable, and a documented one that no longer exists is worse, because a
" vimrc setting it fails silently.
call add(s:out, '--- option documentation')

let s:legacy = ['karate_linter_unclosed_read_rule', 'karate_linter_unclosed_read_level']
let s:readme_lines = s:Read('README.md')
let s:readme = join(s:readme_lines, "\n")

" README documents a level in either of two shapes: spelled out, or as
" `..._level` on the same line as its sibling `_rule`. The second is the house
" style for the rules, so the check has to read it rather than demand the
" first - but it only accepts it next to the sibling, so a level whose rule is
" undocumented too still fails.
function! s:Documented(option) abort
    if s:readme =~# 'g:' . a:option . '\>'
        return v:true
    endif
    let l:sibling = matchstr(a:option, '^\zs.*\ze_level$')
    if empty(l:sibling)
        return v:false
    endif
    for l:line in s:readme_lines
        if l:line =~# 'g:' . l:sibling . '_rule\>' && l:line =~# '\.\.\._level'
            return v:true
        endif
    endfor
    return v:false
endfunction
call s:Ok('every option appears in README.md',
    \ filter(copy(s:options), '!s:Documented(v:val)'), [])

let s:documented = []
for s:line in s:readme_lines
    for s:name in split(s:line, '\W\+')
        " A trailing underscore is the `..._parens_*` glob README uses to name
        " a rule's pair at once, not an option name.
        if s:name =~# '^karate_linter_\w*[^_]$' && index(s:documented, s:name) == -1
            call add(s:documented, s:name)
        endif
    endfor
endfor
let s:known = s:options + s:legacy
call s:Ok('README.md documents no option that does not exist',
    \ filter(copy(s:documented), 'index(s:known, v:val) == -1'), [])

" --- 3. The docs name things that still exist ---
" A document that cites a renamed function reads as authoritative and sends
" the next reader to the wrong file; the profile recipe pointed at a file with
" no hot code in it for two releases that way. Only CamelCase()-shaped spans
" are treated as project functions, which is the whole of this project's
" naming and none of Vim's own lowercase builtins.
call add(s:out, '--- documented identifiers')

let s:src_files = [s:root . '/autoload/karate/linter.vim',
    \ s:root . '/plugin/karate_linter.vim'] + glob(s:root . '/tests/*.vim', 0, 1)
let s:src = []
for s:f in s:src_files
    let s:src += readfile(s:f)
endfor
let s:src_text = join(s:src, "\n")

let s:missing_funcs = []
let s:missing_paths = []
let s:bad_citations = []
for s:doc in s:docs
    for s:span in s:Backticked(s:doc)
        " A function: `Foo()`, `s:Foo()`, `g:Foo()`.
        let s:fn = matchstr(s:span, '\C^\%(g:\|s:\)\?\zs[A-Z][A-Za-z0-9_]*\ze()$')
        if !empty(s:fn)
            let s:def = '\C\%(def\|function!\?\)\s\+\%(g:\|s:\)\?' . s:fn . '\s*('
            if s:src_text !~# s:def && index(s:missing_funcs, s:fn) == -1
                call add(s:missing_funcs, s:fn)
            endif
            continue
        endif
        " A citation: `tests/check_reload.vim:76`.
        let s:cite = matchlist(s:span,
            \ '^\([A-Za-z0-9_./-]\+\.\%(vim\|sh\|md\)\):\(\d\+\)$')
        if !empty(s:cite)
            let s:hits = glob(s:root . '/**/' . fnamemodify(s:cite[1], ':t'), 0, 1)
            if empty(s:hits) || len(readfile(s:hits[0])) < str2nr(s:cite[2])
                call add(s:bad_citations, s:span)
            endif
            continue
        endif
        " A path: `tests/fixtures/12_clean.feature`. Globs and scratch paths
        " under /tmp are deliberately out of scope.
        if s:span =~# '^[A-Za-z0-9_./-]\+\.\%(vim\|sh\|txt\|feature\|md\)$'
            \ && s:span =~# '/' && s:span !~# '^/'
            if !filereadable(s:root . '/' . s:span)
                \ && index(s:missing_paths, s:span) == -1
                call add(s:missing_paths, s:span)
            endif
        endif
    endfor
endfor
call s:Ok('every function the docs name exists', s:missing_funcs, [])
call s:Ok('every path the docs name exists', s:missing_paths, [])
call s:Ok('every file:line citation is in range', s:bad_citations, [])

" --- 4. Fixtures, the baseline and the check scripts agree ---
" The baseline is built from a glob, so a fixture that was added without
" re-recording it is invisible; and a fixture pinned by name in a check script
" but deleted takes that assertion down with it.
call add(s:out, '--- fixture wiring')

let s:fixtures = map(glob(s:root . '/tests/fixtures/*.feature', 0, 1),
    \ 'fnamemodify(v:val, '':t'')')
let s:baseline = s:Text('tests/baseline.sorted.txt')
call s:Ok('every fixture is in the baseline',
    \ filter(copy(s:fixtures), 's:baseline !~# ''=== '' . v:val'), [])

let s:headers = []
for s:line in s:Read('tests/baseline.sorted.txt')
    let s:name = matchstr(s:line, '^=== \zs\S\+\.feature\ze$')
    if !empty(s:name)
        call add(s:headers, s:name)
    endif
endfor
call s:Ok('the baseline lists no fixture that is gone',
    \ filter(copy(s:headers), 'index(s:fixtures, v:val) == -1'), [])

let s:referenced = []
for s:f in glob(s:root . '/tests/check_*.vim', 0, 1)
    for s:line in readfile(s:f)
        for s:name in split(s:line, '[^A-Za-z0-9_.]\+')
            if s:name =~# '^\d\+_\w\+\.feature$' && index(s:referenced, s:name) == -1
                call add(s:referenced, s:name)
            endif
        endfor
    endfor
endfor
call s:Ok('parsed the fixture references at all', len(s:referenced) > 5, v:true)
call s:Ok('every fixture a check script names exists',
    \ filter(copy(s:referenced), 'index(s:fixtures, v:val) == -1'), [])

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/conventions.txt')
qa!

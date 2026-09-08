" Integration checks for the diagnostics pipeline: text properties, signs,
" the error cache, and the debounce/flush behaviour.
"
" Everything is driven through the plugin's real autocommands, so this also
" covers the event wiring itself.
"
"   vim -Nu NONE -es -S tests/check_diagnostics.vim

set nocompatible
set noignorecase
set nomore
set noswapfile
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
        call add(s:out, printf('  FAIL %-46s got=%s want=%s',
            \ a:label, string(a:got), string(a:want)))
    endif
endfunction

function! s:PropCount() abort
    let n = 0
    for lnum in range(1, line('$'))
        let n += len(prop_list(lnum))
    endfor
    return n
endfunction

function! s:SignCount() abort
    let placed = sign_getplaced(bufnr('%'), {'group': 'karate_linter_' . bufnr('%')})
    return empty(placed) ? 0 : len(placed[0].signs)
endfunction

function! s:Fixture(name) abort
    execute 'edit! ' . fnameescape(s:root . '/tests/fixtures/' . a:name)
endfunction

" --- 1. Opening a buffer lints it via autocmd ---
call add(s:out, '--- autocmd on open')
call s:Fixture('01_simple_rules.feature')
call s:Ok('dirty file: report is non-empty', len(KarateLinterReport()) > 0, v:true)
call s:Ok('dirty file: text properties placed', s:PropCount() > 0, v:true)
call s:Ok('dirty file: signs placed', s:SignCount() > 0, v:true)
call s:Ok('dirty file: error cache set', get(b:, 'karate_has_errors', -1), 1)

call s:Fixture('12_clean.feature')
call s:Ok('clean file: no report', len(KarateLinterReport()), 0)
call s:Ok('clean file: no text properties', s:PropCount(), 0)
call s:Ok('clean file: no signs', s:SignCount(), 0)
call s:Ok('clean file: error cache cleared', get(b:, 'karate_has_errors', -1), 0)

" --- 2. Warnings alone must not block auto-format ---
call add(s:out, '--- error cache distinguishes levels')
call s:Fixture('11_structure_no_background.feature')
call s:Ok('warn-only file: cache says no errors', get(b:, 'karate_has_errors', -1), 0)

" --- 3. Re-linting is idempotent (no accumulating properties/signs) ---
call add(s:out, '--- idempotence')
call s:Fixture('01_simple_rules.feature')
let s:props1 = s:PropCount()
let s:signs1 = s:SignCount()
doautocmd BufWinEnter
doautocmd BufWinEnter
call s:Ok('properties do not accumulate', s:PropCount(), s:props1)
call s:Ok('signs do not accumulate', s:SignCount(), s:signs1)

" --- 4. Debounce: an edit schedules, and the real timer applies it ---
call add(s:out, '--- debounce')
call s:Fixture('12_clean.feature')
call s:Ok('clean baseline: no properties', s:PropCount(), 0)

call append(line('$'), "\tGiven this line has a tab")
doautocmd TextChanged
call s:Ok('edit did not lint synchronously', s:PropCount(), 0)

sleep 400m
call s:Ok('timer applied the lint', s:PropCount() > 0, v:true)
call s:Ok('timer set the error cache', get(b:, 'karate_has_errors', -1), 1)

" --- 5. Saving flushes a pending lint even with auto-format disabled ---
call add(s:out, '--- flush on save')
let g:karate_linter_auto_format_on_save = 0
call s:Fixture('12_clean.feature')
call append(line('$'), "\tGiven another tab line")
doautocmd TextChanged
call s:Ok('still pending', s:PropCount(), 0)
doautocmd BufWritePre
call s:Ok('save flushed the lint', s:PropCount() > 0, v:true)
call s:Ok('save refreshed the error cache', get(b:, 'karate_has_errors', -1), 1)

" --- 6. Auto-format on save must not run while errors are pending ---
call add(s:out, '--- auto-format gating')
let g:karate_linter_auto_format_on_save = 1
call s:Fixture('12_clean.feature')
" An error the formatter cannot fix, and at column 0 so that a gate which
" stopped working would be visible: the indent pass would move this line to
" the step level. With a line already correctly indented the check would pass
" whether the gate held or not.
call append(line('$'), '* def broken = read(')
doautocmd TextChanged
" The error only exists in a pending, debounced lint at this point.
" BufWritePre must flush, see it, and refuse to reindent.
let s:before = getline(1, '$')
doautocmd BufWritePre
call s:Ok('buffer untouched when errors pending', getline(1, '$') ==# s:before, v:true)
call s:Ok('cache reflects the pending edit', get(b:, 'karate_has_errors', -1), 1)

" A *fixable* pending error is the other half of that gate: the fixup pass
" runs before it, which is what lets a save get as far as reindenting at all.
call s:Fixture('12_clean.feature')
call append(line('$'), "\tGiven a tab is fixed, not refused")
doautocmd TextChanged
doautocmd BufWritePre
call s:Ok('pending tab was fixed on save', search('\t', 'nw'), 0)
call s:Ok('and the file ends up clean', get(b:, 'karate_has_errors', -1), 0)

" --- 7. Columns are byte offsets, also on non-ASCII lines ---
" prop_add() wants byte columns. In Vim9 script str[i] indexes by CHARACTER,
" so the scanners use strpart(); if that ever regresses, the columns below
" drift by one byte per non-ASCII character to their left.
call add(s:out, '--- byte columns on multibyte lines')
call s:Fixture('30_multibyte_columns.feature')
function! s:TextAt(issue) abort
    let line = getline(a:issue.lnum)
    return strpart(line, a:issue.col - 1, a:issue.end_col - a:issue.col)
endfunction
let s:found = {}
for s:issue in KarateLinterReport()
    let s:found[s:issue.text] = s:TextAt(s:issue)
endfor
call s:Ok('unbalanced brace after cyrillic',
    \ get(s:found, "Unclosed '{'", ''), "{ имя: 'значение'")
call s:Ok('table cell after a cyrillic cell',
    \ get(s:found, "Header 'лишний' is defined in the Examples table but not used in the Scenario Outline.", ''),
    \ 'лишний')

" --- 8. Line length is measured in display columns, not bytes ---
" Counting bytes halved the effective limit for non-ASCII text. The anchor has
" to be the byte offset of the character sitting on column max+1, so that the
" highlight starts on a character boundary rather than inside one.
call add(s:out, '--- line length in columns')
call s:Fixture('22_long_multibyte_message.feature')
let s:toolong = filter(KarateLinterReport(), 'v:val.text =~# "too long"')
call s:Ok('a 131-column cyrillic line is reported', len(s:toolong), 1)
if len(s:toolong) == 1
    let s:line = getline(s:toolong[0].lnum)
    let s:col = s:toolong[0].col
    call s:Ok('anchor is past the limit, not at byte 121', s:col > 121, v:true)
    call s:Ok('everything before the anchor fits exactly',
        \ strdisplaywidth(strpart(s:line, 0, s:col - 1)), 120)
    call s:Ok('anchor is on a character boundary',
        \ byteidx(s:line, charidx(s:line, s:col - 1)), s:col - 1)
endif

call s:Fixture('30_multibyte_columns.feature')
call s:Ok('190 bytes but 110 columns is not reported',
    \ len(filter(KarateLinterReport(), 'v:val.text =~# "too long"')), 0)

" --- 9. One sign per line, and an error outranks a warning there ---
" Sign ids are derived from the line number, so a line with several
" diagnostics only gets one sign. Which icon it was used to depend on the
" order the rules ran in, so a warning could mask an error.
call add(s:out, '--- sign level per line')
call s:Fixture('14_parens_bad.feature')
function! s:SignOn(lnum) abort
    let placed = sign_getplaced(bufnr('%'), {'group': 'karate_linter_' . bufnr('%'), 'lnum': a:lnum})
    if empty(placed) || empty(placed[0].signs)
        return '<none>'
    endif
    return placed[0].signs[0].name
endfunction
" L11 carries both an unused-variable warning and an unclosed-paren error.
let s:levels = map(filter(KarateLinterReport(), 'v:val.lnum == 11'), 'v:val.level')
call s:Ok('L11 really has a warning and an error',
    \ sort(copy(s:levels)), ['KarateLintError', 'KarateLintWarn'])
call s:Ok('the error wins the gutter', s:SignOn(11), 'KarateLintError')
call s:Ok('one sign per line, not per diagnostic',
    \ s:SignCount(), len(uniq(sort(map(KarateLinterReport(), 'v:val.lnum')))))

" --- 10. No stray public surface beyond the documented entry point ---
call add(s:out, '--- public api')
call s:Ok('KarateLinterReport exists', exists('*KarateLinterReport'), 1)
call s:Ok('no test-only SID hook left behind', exists('*KarateLinterSid'), 0)

" --- 11. A placeholder inside a docstring body is still a usage ---
" Gherkin substitutes <placeholder> into a docstring payload before Karate
" ever sees it, so the usage scan in LintScenarioOutlines() deliberately does
" not skip docstring_body - only *definitions* are skipped (invariant 3).
" Narrowing that loop to the statement lines leaves every other assertion in
" the suite green: in this fixture both Examples columns are used only inside
" the payload, and skipping it invents two "unused header" warnings.
call add(s:out, '--- placeholders inside a docstring body')
call s:Fixture('34_docstring_placeholder_usage.feature')
call s:Ok('a header used only in a docstring is not called unused',
    \ len(filter(KarateLinterReport(), 'v:val.text =~# "not used in the Scenario Outline"')), 0)
call s:Ok('and the fixture is clean of everything else',
    \ len(KarateLinterReport()), 0)

" --- 12. The structural rules must not fire on near misses ---
" Nine structural rules had `12_clean.feature` as their entire negative half,
" so a false positive in one could only ever surface as a baseline line.
" Fixture 36 is a real negative: Gherkin keywords in comments and in a
" docstring payload, inline XML inside an outline, and a tagged `Examples:`
" block - the last of which used to be reported twice over, once as an outline
" with no table and once as an orphaned Examples.
" Fixture 37 pins the other answer, so that "tags never end an outline" is
" not a way to make 36 pass.
call add(s:out, '--- structural near misses')
call s:Fixture('36_structural_near_misses.feature')
call s:Ok('near misses report nothing at all', len(KarateLinterReport()), 0)

call s:Fixture('37_tag_ends_outline.feature')
call s:Ok('a tag introducing a scenario still ends an outline',
    \ len(filter(KarateLinterReport(), 'v:val.text =~# "corresponding"')), 1)
call s:Ok('and that is the only finding there', len(KarateLinterReport()), 1)

call add(s:out, '')
call add(s:out, s:fail == 0 ? 'RESULT: ALL OK' : printf('RESULT: %d FAILURE(S)', s:fail))
call writefile(s:out, s:root . '/tests/diagnostics.txt')
qa!

" ~/.vim/plugin/karate_linter.vim

" Проверяем, что плагин не загружается повторно
if exists("g:loaded_karate_linter")
  finish
endif
let g:loaded_karate_linter = 1


" --- КОНФИГУРАЦИЯ ---
let s:defaults = {
    \ 'karate_linter_max_line_length': 120,
    \ 'karate_linter_max_line_length_level': 'KarateLintWarn',
    \ 'karate_linter_tabs_rule': 1,
    \ 'karate_linter_tabs_level': 'KarateLintError',
    \ 'karate_linter_trailing_space_rule': 1,
    \ 'karate_linter_trailing_space_level': 'KarateLintError',
    \ 'karate_linter_and_but_rule': 1,
    \ 'karate_linter_and_but_level': 'KarateLintWarn',
    \ 'karate_linter_no_space_after_keyword_rule': 1,
    \ 'karate_linter_no_space_after_keyword_level': 'KarateLintError',
    \ 'karate_linter_auto_format_on_save': 1,
    \ 'karate_linter_missing_examples_rule': 1,
    \ 'karate_linter_call_read_space_rule': 1,
    \ 'karate_linter_call_read_space_level': 'KarateLintError',
    \ 'karate_linter_unclosed_read_rule': 1,
    \ 'karate_linter_unclosed_read_level': 'KarateLintError',
    \ 'karate_linter_orphaned_examples_rule': 1,
    \ 'karate_linter_orphaned_examples_level': 'KarateLintError',
    \ 'karate_linter_unclosed_docstring_rule': 1,
    \ 'karate_linter_unclosed_docstring_level': 'KarateLintError',
     \ }

for var_name in keys(s:defaults)
    if !exists('g:' . var_name)
        let default_value = s:defaults[var_name]
        execute 'let g:' . var_name . ' = ' . string(default_value)
    endif
endfor
unlet s:defaults
" --- КОНЕЦ КОНФИГУРАЦИИ ---


augroup KarateLinter
  autocmd!

  highlight default link KarateLintError Error
  highlight default link KarateLintWarn Todo

  function! s:clear_karate_lint()
    if exists("w:karate_lint_matches")
      for match_id in w:karate_lint_matches
        silent! call matchdelete(match_id)
      endfor
      unlet w:karate_lint_matches
    endif
  endfunction

  function! s:find_invalid_outlines()
    let l:invalid_outline_lines = []
    let l:outline_start_line = 0
    for l:line_num in range(1, line('$'))
      let l:line_text = getline(l:line_num)
      let l:is_outline = l:line_text =~ '^\s*Scenario Outline:'
      let l:is_normal_scenario = l:line_text =~ '^\s*Scenario:' && !l:is_outline
      let l:is_tag = l:line_text =~ '^\s*@'
      let l:is_examples = l:line_text =~ '^\s*Examples:'
      if l:is_normal_scenario || l:is_tag
        if l:outline_start_line > 0
          call add(l:invalid_outline_lines, l:outline_start_line)
          let l:outline_start_line = 0
        endif
      endif
      if l:is_outline
        if l:outline_start_line > 0
            call add(l:invalid_outline_lines, l:outline_start_line)
        endif
        let l:outline_start_line = l:line_num
      endif
      if l:is_examples
        if l:outline_start_line > 0
          let l:outline_start_line = 0
        endif
      endif
    endfor
    if l:outline_start_line > 0
      call add(l:invalid_outline_lines, l:outline_start_line)
    endif
    return l:invalid_outline_lines
  endfunction

  " НОВАЯ ФУНКЦИЯ
  function! s:find_orphaned_examples()
    let l:orphaned_lines = []
    let l:outline_context_active = 0 " Становится 1 после 'Scenario Outline'
    for l:line_num in range(1, line('$'))
      let l:line_text = getline(l:line_num)

      let l:is_outline = l:line_text =~ '^\s*Scenario Outline:'
      let l:is_normal_scenario = l:line_text =~ '^\s*Scenario:' && !l:is_outline
      let l:is_tag = l:line_text =~ '^\s*@'
      let l:is_examples = l:line_text =~ '^\s*Examples:'

      " Новый сценарий или тег сбрасывает ожидание 'Examples'
      if l:is_normal_scenario || l:is_tag
        let l:outline_context_active = 0
      endif

      " Новый 'Scenario Outline' начинает контекст
      if l:is_outline
        let l:outline_context_active = 1
      endif

      if l:is_examples
        if l:outline_context_active
          " Это валидный блок 'Examples', он завершает контекст
          let l:outline_context_active = 0
        else
          " Это "осиротевший" блок 'Examples'
          call add(l:orphaned_lines, l:line_num)
        endif
      endif
    endfor
    return l:orphaned_lines
  endfunction

  function! s:find_unclosed_docstring()
    let l:last_occurrence_line = 0
    let l:count = 0
    for l:line_num in range(1, line('$'))
      let l:line_text = getline(l:line_num)
      let l:occurrences_in_line = len(split(l:line_text, '"""', 1)) - 1

      if l:occurrences_in_line > 0
        let l:count += l:occurrences_in_line
        let l:last_occurrence_line = l:line_num
      endif
    endfor

    if l:count % 2 != 0
      return l:last_occurrence_line
    else
      return 0
    endif
  endfunction

  function! s:setup_karate_lint()
    call s:clear_karate_lint()
    let w:karate_lint_matches = []
    let w:karate_has_errors = 0 " Инициализируем флаг

    let l:cursor_pos = getcurpos() " Сохраняем курсор для поиска

    " Правило: Табы
    if g:karate_linter_tabs_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_tabs_level, '\t'))
      if !w:karate_has_errors && g:karate_linter_tabs_level == 'KarateLintError'
        if search('\t', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Правило: Лишние пробелы в конце строки
    if g:karate_linter_trailing_space_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_trailing_space_level, '\s\+$'))
      if !w:karate_has_errors && g:karate_linter_trailing_space_level == 'KarateLintError'
        if search('\s\+$', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Правило: Длина строки
    if g:karate_linter_max_line_length > 0
      let l:pattern = '\%>' . g:karate_linter_max_line_length . 'v.\+'
      call add(w:karate_lint_matches, matchadd(g:karate_linter_max_line_length_level, l:pattern))
      if !w:karate_has_errors && g:karate_linter_max_line_length_level == 'KarateLintError'
        if search(l:pattern, 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Правило: 'And' вместо 'But' (стилистика)
    if g:karate_linter_and_but_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_and_but_level, '^\s*But\s'))
      if !w:karate_has_errors && g:karate_linter_and_but_level == 'KarateLintError'
          if search('^\s*But\s', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Правило: Нет пробела после ключевого слова
    if g:karate_linter_no_space_after_keyword_rule
      let l:pattern = '^\s*\(\*\|Given\|When\|Then\|And\|But\)\S'
      call add(w:karate_lint_matches, matchadd(g:karate_linter_no_space_after_keyword_level, l:pattern))
      if !w:karate_has_errors && g:karate_linter_no_space_after_keyword_level == 'KarateLintError'
        if search(l:pattern, 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Правило: 'Scenario Outline' без 'Examples'
    if g:karate_linter_missing_examples_rule
      let l:invalid_lines = s:find_invalid_outlines()
      if !empty(l:invalid_lines)
        let w:karate_has_errors = 1 " Это правило всегда является ошибкой
        for line_num in l:invalid_lines
          let l:pattern = '\%' . line_num . 'l.\+'
          call add(w:karate_lint_matches, matchadd('KarateLintError', l:pattern))
        endfor
      endif
    endif

    " Правило: 'callread' вместо 'call read'
    if g:karate_linter_call_read_space_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_call_read_space_level, '\bcallread('))
      if !w:karate_has_errors && g:karate_linter_call_read_space_level == 'KarateLintError'
          if search('\bcallread(', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif
    
    " Правило: незакрытая функция 'read'
    if g:karate_linter_unclosed_read_rule
      call add(w:karate_lint_matches, matchadd(g:karate_linter_unclosed_read_level, '^\s*\(Given\|When\|Then\|And\|But\|\*\).*read\([^)]*$\)'))
       if !w:karate_has_errors && g:karate_linter_unclosed_read_level == 'KarateLintError'
          if search('^\s*\(Given\|When\|Then\|And\|But\|\*\).*read\([^)]*$\)', 'nwc') > 0 | let w:karate_has_errors = 1 | endif
      endif
    endif

    " Правило: 'Examples' без 'Scenario Outline'
    if g:karate_linter_orphaned_examples_rule
      let l:invalid_lines = s:find_orphaned_examples()
      if !empty(l:invalid_lines)
          if g:karate_linter_orphaned_examples_level == 'KarateLintError'
              let w:karate_has_errors = 1
          endif
          for line_num in l:invalid_lines
              let l:pattern = '\%' . line_num . 'l.\+'
              call add(w:karate_lint_matches, matchadd(g:karate_linter_orphaned_examples_level, l:pattern))
          endfor
      endif
    endif

    " Правило: незакрытый DocString '"""'
    if g:karate_linter_unclosed_docstring_rule
      let l:unclosed_line_num = s:find_unclosed_docstring()
      if l:unclosed_line_num > 0
        if g:karate_linter_unclosed_docstring_level == 'KarateLintError'
          let w:karate_has_errors = 1
        endif
        let l:pattern = '\%' . l:unclosed_line_num . 'l.\+'
        call add(w:karate_lint_matches, matchadd(g:karate_linter_unclosed_docstring_level, l:pattern))
      endif
    endif
    
    call setpos('.', l:cursor_pos) " Восстанавливаем курсор
endfunction

  function! s:has_errors()
    return get(w:, 'karate_has_errors', 0)
  endfunction

  function! s:auto_format_on_save()
    if !g:karate_linter_auto_format_on_save | return | endif
    if s:has_errors() == 0
      let l:save_cursor = getcurpos()
      silent! normal! gg=G
      call setpos('.', l:save_cursor)
    endif
  endfunction

  autocmd BufEnter,BufWinEnter,TextChanged,TextChangedI *.feature call s:setup_karate_lint()
  autocmd BufLeave,WinLeave *.feature call s:clear_karate_lint()
  autocmd BufWritePre *.feature call s:auto_format_on_save()

augroup END

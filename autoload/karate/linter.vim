vim9script
# Karate feature-file linter - engine.
#
# Loaded lazily through `import autoload` from plugin/karate_linter.vim, so
# none of this is parsed or compiled until the first .feature file is touched.
#
# Byte offsets, not character offsets: every 'col' in a diagnostic ends up in
# prop_add(), which wants byte columns. Note that in Vim9 script `str[i]`
# indexes by CHARACTER, so the scanners below use strpart(str, i, 1) instead.

# --- Diagnostics setup ---------------------------------------------------

if empty(prop_type_get('karate_lint_error'))
  prop_type_add('karate_lint_error', {highlight: 'KarateLintError'})
endif
if empty(prop_type_get('karate_lint_warn'))
  prop_type_add('karate_lint_warn', {highlight: 'KarateLintWarn'})
endif

sign_define('KarateLintError', {text: '>>', texthl: 'KarateLintError'})
sign_define('KarateLintWarn', {text: 'W>', texthl: 'KarateLintWarn'})

const SIGN_ID_BASE = 1000
const ERROR_LEVEL = 'KarateLintError'

# Rules applied line by line.
#   pattern      - decides where the diagnostic is anchored (column range)
#   line_pattern - optional pre-filter deciding whether the rule applies
#   in_docstring - rule still applies inside a docstring body. Docstring
#                  bodies are JSON/JS/XML payload, not Karate syntax, so by
#                  default rules stay out of them; tabs are the exception,
#                  they break indentation anywhere.
const SIMPLE_LINE_RULES = [
  {name: 'tabs', pattern: '\t', text: 'Tabs are not allowed', in_docstring: true},
  {name: 'trailing_space', pattern: '\s\+$', text: 'Trailing whitespace'},
  {name: 'and_but', pattern: 'But', line_pattern: '^\s*But\s',
   text: "Use 'And' instead of 'But' for consistency"},
  {name: 'no_space_after_keyword',
   pattern: '^\s*\zs\(\*\|Given\|When\|Then\|And\|But\)\S',
   text: 'Missing space after keyword (Given, When, Then, etc.)'},
  {name: 'call_read_space', pattern: '\<callread(',
   text: "Use 'call read' instead of 'callread'"},
]

const STEP_PATTERN = '\C^\s*\%(\*\|Given\|When\|Then\|And\|But\)\s'
const DOCSTRING_PATTERN = '^\s*"""\s*$'
const CLOSERS = {')': '(', '}': '{', ']': '['}

# A complete string literal in any of Karate's three quote styles, backslash
# escapes included. Used to blank strings out before the cheap balance test.
const STRING_LITERAL = '\%('
  .. '"\%([^"\\]\|\\.\)*"'
  .. '\|' .. '''\%([^''\\]\|\\.\)*'''
  .. '\|' .. '`\%([^`\\]\|\\.\)*`'
  .. '\)'

def RuleOn(name: string): bool
  return get(g:, 'karate_linter_' .. name .. '_rule', 0) != 0
enddef

def RuleLevel(name: string): string
  return get(g:, 'karate_linter_' .. name .. '_level', ERROR_LEVEL)
enddef

# Same semantics as the old s:trim(): only spaces and tabs, so that a cell's
# reported column (computed from '^\s*') always agrees with its text.
def Trim(text: string): string
  return substitute(text, '^\s*\|\s*$', '', 'g')
enddef


# --- Shared helpers ------------------------------------------------------

# True when pattern matches at least one line that is not docstring payload.
# Keeps match()'s early exit: it restarts the search past a docstring hit
# instead of walking the whole buffer.
def HasLineOutsideDocstring(lines: list<string>, pattern: string,
    docstring_body: dict<bool>): bool
  var idx = 0
  while true
    idx = match(lines, pattern, idx)
    if idx < 0
      return false
    endif
    if !has_key(docstring_body, string(idx + 1))
      return true
    endif
    idx += 1
  endwhile
  return false
enddef

# Anchors a whole-line diagnostic.
#
# There is deliberately no 'already reported this line' set: two different
# problems on one line are two findings, and suppressing the second one used
# to hide "Missing 'Scenario:'" whenever 'Feature:' was missing too.
#
# An empty anchor line still gets a one-cell span; such diagnostics used to be
# dropped outright, so a file starting with a blank line reported nothing.
def AddLineDiag(report: list<dict<any>>, lines: list<string>, lnum: number,
    text: string, level: string)
  var line_content = get(lines, lnum - 1, '')
  var start_byte = match(line_content, '\S')
  var start_col = start_byte > -1 ? start_byte + 1 : 1
  add(report, {
    lnum: lnum,
    col: start_col,
    end_col: max([len(line_content) + 1, start_col + 1]),
    text: text,
    level: level,
  })
enddef

# Byte offset of the first character that sits past maxwidth display columns.
#
# The width of a prefix is measured with strdisplaywidth() rather than by
# adding up per-character widths, because a tab's width depends on where it
# starts. Only ever called for a line already known to be too long, so the
# per-character loop costs nothing in the common case.
def ColumnBeyondWidth(line: string, maxwidth: number): number
  var char_count = strchars(line)
  var i = 1
  while i <= char_count
    var b = byteidx(line, i)
    if b < 0
      break
    endif
    if strdisplaywidth(strpart(line, 0, b)) > maxwidth
      return byteidx(line, i - 1)
    endif
    i += 1
  endwhile
  return len(line)
enddef

# Where a file-level diagnostic points: the first line with any content, so
# the highlight lands on real text rather than on leading blank lines.
def FirstContentLine(lines: list<string>): number
  var idx = match(lines, '\S')
  return idx < 0 ? 1 : idx + 1
enddef

# Splits a Gherkin table row into cells, keeping the byte position of each.
# Positions come from the parse instead of a later search, so no pattern is
# ever built out of user text.
#
# Returns [] for a line that is not a table row. Empty cells are preserved:
# they still count as columns. A pipe escaped as '\|' is cell content.
def ParseTableRow(line: string): list<dict<any>>
  var bars: list<number> = []
  var i = 0
  var line_len = len(line)
  while i < line_len
    var c = strpart(line, i, 1)
    if c == '\'
      i += 2
      continue
    endif
    if c == '|'
      add(bars, i)
    endif
    i += 1
  endwhile

  if len(bars) < 2
    return []
  endif

  var cells: list<dict<any>> = []
  var idx = 0
  while idx < len(bars) - 1
    var start = bars[idx] + 1
    var raw = strpart(line, start, bars[idx + 1] - start)
    var lead = matchstr(raw, '^\s*')
    var text = Trim(raw)
    var col = start + len(lead) + 1
    # Empty cells get a one-column span so the range stays highlightable.
    add(cells, {
      text: text,
      col: col,
      end_col: col + (empty(text) ? 1 : len(text)),
    })
    idx += 1
  endwhile
  return cells
enddef


# --- Delimiter scanning --------------------------------------------------

# Cheap, sound pre-check: is this line worth a character-by-character scan?
#
# The scan is a loop over every byte, and on a realistic Karate file nearly
# every step contains a quote - running it everywhere cost more than the rest
# of the linter put together. This does the same job with two substitute()
# calls and a collapse loop over a handful of bracket characters.
#
# It never misses a problem: complete strings are blanked out, so a surviving
# quote means an unterminated one, and matched bracket pairs are collapsed
# until nothing more can go, so anything left is genuinely unbalanced - ')('
# included, which a simple count comparison would miss.
def LineMayBeUnbalanced(line: string): bool
  var stripped = substitute(line, STRING_LITERAL, '', 'g')
  stripped = substitute(stripped, ':\@<!//.*$', '', '')

  if stripped =~# '[''"`]'
    return true
  endif

  var brackets = substitute(stripped, '[^(){}[\]]', '', 'g')
  while !empty(brackets)
    var previous = brackets
    brackets = substitute(brackets, '()\|{}\|\[\]', '', 'g')
    if brackets == previous
      break
    endif
  endwhile

  return !empty(brackets)
enddef

# Scans a step line for the first delimiter problem. Returns {} when the line
# is well formed, otherwise one of:
#   {kind: 'string',  idx: <byte>, char: <quote>}
#   {kind: 'bracket', idx: <byte>, char: '(' / '{' / '['}
#
# Delimiters inside string literals do not count, and a trailing JavaScript
# line comment is ignored - except for the '//' in a URL such as http://x.
def ScanDelimiters(line: string): dict<any>
  var line_len = len(line)
  var open_stack: list<dict<any>> = []
  var quote = ''
  var quote_idx = -1
  var i = 0

  while i < line_len
    var c = strpart(line, i, 1)

    if !empty(quote)
      # Inside a string: only an escape or the closing quote matter.
      if c == '\'
        i += 2
        continue
      endif
      if c == quote
        quote = ''
      endif
      i += 1
      continue
    endif

    if c == "'" || c == '"' || c == '`'
      quote = c
      quote_idx = i
      i += 1
      continue
    endif

    if c == '/' && i + 1 < line_len && strpart(line, i + 1, 1) == '/'
      if i == 0 || strpart(line, i - 1, 1) != ':'
        break
      endif
      i += 2
      continue
    endif

    if c == '(' || c == '{' || c == '['
      add(open_stack, {char: c, idx: i})
    elseif has_key(CLOSERS, c)
      # A closer that does not match the innermost opener closes nothing, the
      # same way a stray ')' always has: it must not cancel out a bracket that
      # really is left open.
      if !empty(open_stack) && open_stack[-1].char == CLOSERS[c]
        remove(open_stack, -1)
      endif
    endif

    i += 1
  endwhile

  # An unterminated string swallows the rest of the line, so it is reported
  # alone: any bracket after the opening quote was never really seen, and
  # piling those on top would bury the root cause.
  if !empty(quote)
    return {kind: 'string', idx: quote_idx, char: quote}
  endif
  if !empty(open_stack)
    return {kind: 'bracket', idx: open_stack[0].idx, char: open_stack[0].char}
  endif
  return {}
enddef

# Unbalanced brackets and unterminated strings in Karate steps.
#
# Only step lines are considered ('*', Given/When/Then/And/But). Feature and
# Scenario titles, descriptions, tags, tables and whole-line comments are out
# of scope by construction; docstring bodies are excluded by the caller.
def LintDelimiters(lines: list<string>, docstring_body: dict<bool>): list<dict<any>>
  var report: list<dict<any>> = []
  var brackets_on = RuleOn('unbalanced_parens')
  var strings_on = RuleOn('unterminated_string')
  if !brackets_on && !strings_on
    return report
  endif

  var bracket_level = RuleLevel('unbalanced_parens')
  var string_level = RuleLevel('unterminated_string')
  var lnum = 0

  for line in lines
    lnum += 1
    if has_key(docstring_body, string(lnum))
      continue
    endif

    # Cheapest test first: a line with no delimiter at all cannot be
    # unbalanced, and that covers most 'And match a == b' style steps.
    if line !~# '[(){}[\]''"`]'
      continue
    endif
    if line !~# STEP_PATTERN
      continue
    endif
    if !LineMayBeUnbalanced(line)
      continue
    endif

    # Only reached for a line that really is broken, so the character scan -
    # which is what pins down the exact column - is paid once per problem
    # rather than once per step.
    var problem = ScanDelimiters(line)
    if empty(problem)
      continue
    endif

    if problem.kind == 'string'
      if !strings_on
        continue
      endif
      add(report, {
        lnum: lnum,
        col: problem.idx + 1,
        end_col: len(line) + 1,
        text: printf('Unterminated string literal (no closing %s)', problem.char),
        level: string_level,
      })
      continue
    endif

    if !brackets_on
      continue
    endif

    var text: string
    var col: number
    if problem.char == '('
      # Only report call parentheses: 'name(' or 'name ('. A bare grouping
      # paren is left alone, per the agreed scope. Braces and brackets need no
      # such test: in Karate they are always data literals, never grouping.
      var before = strpart(line, 0, problem.idx)
      var [name_text, name_start, name_end] = matchstrpos(before, '[A-Za-z_$][A-Za-z0-9_$.]*\s*$')
      if name_start < 0
        continue
      endif
      text = printf("Unclosed '(' in call to '%s'", substitute(name_text, '\s\+$', '', ''))
      col = name_start + 1
    else
      text = printf("Unclosed '%s'", problem.char)
      col = problem.idx + 1
    endif

    add(report, {
      lnum: lnum,
      col: col,
      end_col: len(line) + 1,
      text: text,
      level: bracket_level,
    })
  endfor

  return report
enddef


# --- Outline / Examples helpers ------------------------------------------

def FindAllDocstringRanges(lines: list<string>): list<list<number>>
  var ranges: list<list<number>> = []
  var in_docstring = false
  var start_lnum = 0
  var lnum = 0

  for line in lines
    lnum += 1
    if stridx(line, '"""') < 0
      continue
    endif
    if line =~# DOCSTRING_PATTERN
      if !in_docstring
        start_lnum = lnum
        in_docstring = true
      else
        add(ranges, [start_lnum, lnum])
        in_docstring = false
      endif
    endif
  endfor
  return ranges
enddef

# Outlines without an Examples block, and Examples blocks without an outline.
#
# These were two functions walking the buffer separately and computing the
# same four predicates on every line - eight regular expressions per line for
# what is really one traversal. They are independent state machines over the
# same input, so they share a pass now.
#
# Pure Vim, no subprocess. This used to shell out to awk on every keystroke;
# the \C prefixes keep it case-sensitive exactly like awk was, regardless of
# the user's 'ignorecase'.
def ScanOutlines(lines: list<string>, docstring_body: dict<bool>): dict<list<number>>
  var invalid: list<number> = []
  var orphaned: list<number> = []
  var outline_start = 0        # an outline still waiting for its Examples
  var outline_context = false  # an Examples here would belong to an outline

  for line_num in range(1, len(lines))
    if has_key(docstring_body, string(line_num))
      continue
    endif
    var line_text = lines[line_num - 1]
    var is_outline = line_text =~# '\C^[ 	]*Scenario Outline:'
    var is_normal_scenario = line_text =~# '\C^[ 	]*Scenario:' && !is_outline
    var is_tag = line_text =~# '\C^[ 	]*@'
    var is_examples = line_text =~# '\C^[ 	]*Examples:'

    # A new scenario or tag ends any pending outline and resets the
    # expectation of an Examples block.
    if is_normal_scenario || is_tag
      if outline_start > 0
        add(invalid, outline_start)
        outline_start = 0
      endif
      outline_context = false
    endif

    if is_outline
      if outline_start > 0
        add(invalid, outline_start)
      endif
      outline_start = line_num
      outline_context = true
    endif

    if is_examples
      if outline_start > 0
        outline_start = 0
      endif
      if outline_context
        outline_context = false
      else
        add(orphaned, line_num)
      endif
    endif
  endfor

  if outline_start > 0
    add(invalid, outline_start)
  endif

  return {invalid: invalid, orphaned: orphaned}
enddef

# One Examples table's internal consistency: duplicated column names, data
# rows whose cell count disagrees with the header, and a header with no data
# rows under it (an outline that silently never runs).
def LintExamplesTable(lines: list<string>, docstring_body: dict<bool>,
    header_lnum: number, outline_end: number,
    header_cells: list<dict<any>>): list<dict<any>>
  var report: list<dict<any>> = []
  var level = RuleLevel('examples_table')

  # Duplicate column names: the later one wins in Gherkin, so the earlier
  # column is silently unreachable.
  var seen: dict<bool> = {}
  for cell in header_cells
    if empty(cell.text)
      continue
    endif
    if has_key(seen, cell.text)
      add(report, {
        lnum: header_lnum, col: cell.col, end_col: cell.end_col,
        text: printf("Duplicate Examples column '%s'", cell.text),
        level: level,
      })
    endif
    seen[cell.text] = true
  endfor

  # Data rows run contiguously under the header until the table stops.
  var expected = len(header_cells)
  var rows = 0
  var lnum = header_lnum + 1

  while lnum <= outline_end
    if has_key(docstring_body, string(lnum))
      break
    endif
    var line = lines[lnum - 1]
    if line =~# '^\s*$' || line =~# '^\s*#'
      lnum += 1
      continue
    endif
    if line !~# '^\s*|.*|$'
      break
    endif

    rows += 1
    var cells = ParseTableRow(line)
    if len(cells) != expected
      add(report, {
        lnum: lnum,
        col: match(line, '\S') + 1,
        end_col: len(line) + 1,
        text: printf('Examples row has %d cell%s, the header has %d',
                     len(cells), len(cells) == 1 ? '' : 's', expected),
        level: level,
      })
    endif
    lnum += 1
  endwhile

  if rows == 0
    var header_line = lines[header_lnum - 1]
    add(report, {
      lnum: header_lnum,
      col: match(header_line, '\S') + 1,
      end_col: len(header_line) + 1,
      text: 'Examples table has no data rows',
      level: level,
    })
  endif

  return report
enddef

# Docstring payload is skipped when locating block boundaries and the Examples
# table, but NOT when collecting '<placeholder>' usages: Gherkin substitutes
# Examples values inside docstrings too, so a placeholder used only in a JSON
# payload is a real usage of that header.
def LintScenarioOutlines(lines: list<string>, docstring_body: dict<bool>): list<dict<any>>
  var report: list<dict<any>> = []
  var num_lines = len(lines)

  # Step 1: find all Scenario Outline blocks.
  var outlines: list<dict<number>> = []
  var current: dict<number> = {}
  var in_outline = false
  var lnum = 1
  while lnum <= num_lines
    if has_key(docstring_body, string(lnum))
      lnum += 1
      continue
    endif
    var line = lines[lnum - 1]

    if line =~# '^\s*Scenario Outline:'
      if in_outline
        current.end = lnum - 1
        add(outlines, current)
      endif
      current = {start: lnum}
      in_outline = true
    elseif line =~# '^\s*\(@\|Scenario:\)'
      if in_outline
        current.end = lnum - 1
        add(outlines, current)
        in_outline = false
      endif
    endif
    lnum += 1
  endwhile
  if in_outline
    current.end = num_lines
    add(outlines, current)
  endif

  if empty(outlines)
    return report
  endif

  var table_rule = RuleOn('examples_table')
  var placeholder_rule = RuleOn('undefined_placeholder')
  var header_rule = RuleOn('unused_header')

  for outline in outlines
    var placeholders: dict<number> = {}
    var table_headers: list<string> = []
    var examples_lnum = -1
    var header_lnum = -1

    # Find the Examples: line and the header row under it.
    for lnum_in_outline in range(outline.start, outline.end)
      if has_key(docstring_body, string(lnum_in_outline))
        continue
      endif
      var line = lines[lnum_in_outline - 1]
      if line =~# '^\s*Examples:'
        examples_lnum = lnum_in_outline
        var candidate = lnum_in_outline + 1
        while candidate <= outline.end
          var header_line = lines[candidate - 1]
          if header_line =~# '^\s*|.*|$'
            header_lnum = candidate
            break
          elseif header_line !~# '^\s*$' && header_line !~# '^\s*#'
            break
          endif
          candidate += 1
        endwhile
        break
      endif
    endfor

    # Only reached when an 'Examples:' block exists at all - an outline with
    # no Examples at all is the missing_examples rule's business.
    if table_rule && examples_lnum > -1 && header_lnum == -1
      var examples_line = lines[examples_lnum - 1]
      var indent = match(examples_line, '\S')
      add(report, {
        lnum: examples_lnum,
        col: (indent > -1 ? indent : 0) + 1,
        end_col: len(examples_line) + 1,
        text: "'Examples' block has no table",
        level: RuleLevel('examples_table'),
      })
    endif

    if header_lnum == -1
      continue
    endif

    # Empty cells stay in header_cells (they still count as columns) but out
    # of table_headers, which is the list of names a placeholder can name.
    var header_cells = ParseTableRow(lines[header_lnum - 1])
    for cell in header_cells
      if !empty(cell.text)
        add(table_headers, cell.text)
      endif
    endfor

    if table_rule
      extend(report, LintExamplesTable(lines, docstring_body, header_lnum,
        outline.end, header_cells))
    endif

    # Placeholders used in the outline body.
    var placeholder_pattern = '<\([^<>]\+\)>'
    var end_of_steps = examples_lnum > -1 ? examples_lnum - 1 : outline.end
    for lnum_in_steps in range(outline.start, end_of_steps)
      var line = lines[lnum_in_steps - 1]
      var match_start = 0
      while match_start >= 0
        var match_idx = match(line, placeholder_pattern, match_start)
        if match_idx != -1
          var placeholder = matchstr(line, placeholder_pattern, match_idx)
          var var_name = strpart(placeholder, 1, len(placeholder) - 2)
          if !has_key(placeholders, var_name)
            placeholders[var_name] = lnum_in_steps
          endif
          match_start = match_idx + len(placeholder)
        else
          match_start = -1
        endif
      endwhile
    endfor

    if placeholder_rule
      for used_var in keys(placeholders)
        if index(table_headers, used_var) == -1
          var lnum_of_error = placeholders[used_var]
          var line_content = lines[lnum_of_error - 1]

          # stridx(), not match(): the placeholder name comes from the file
          # and may contain regular-expression metacharacters. Building a
          # pattern out of it found the wrong offset, or none at all - and a
          # col of 0 then made prop_add() throw E964 and kill the render.
          var needle = '<' .. used_var .. '>'
          var idx = stridx(line_content, needle)
          if idx < 0
            continue
          endif

          add(report, {
            lnum: lnum_of_error,
            col: idx + 1,
            end_col: idx + 1 + len(needle),
            text: "Placeholder '<" .. used_var .. ">' is not defined in the Examples table.",
            level: RuleLevel('undefined_placeholder'),
          })
        endif
      endfor
    endif

    # Positions come from the parsed cells, so no pattern is built out of the
    # header text either.
    if header_rule
      var used_vars = keys(placeholders)
      for cell in header_cells
        if empty(cell.text)
          continue
        endif
        if index(used_vars, cell.text) == -1
          add(report, {
            lnum: header_lnum,
            col: cell.col,
            end_col: cell.end_col,
            text: "Header '" .. cell.text .. "' is defined in the Examples table but not used in the Scenario Outline.",
            level: RuleLevel('unused_header'),
          })
        endif
      endfor
    endif
  endfor

  return report
enddef


# --- Variable rules ------------------------------------------------------

def FindUnusedVariables(lines: list<string>, docstring_body: dict<bool>): list<dict<any>>
  var report: list<dict<any>> = []
  if !RuleOn('unused_variable')
    return report
  endif

  # Pass 1: definitions.
  # Docstring payload is skipped: a '* def x' line inside a JSON or JS block
  # is not a Karate definition. Only DEFINITIONS are skipped - usages are
  # deliberately counted everywhere, because Karate evaluates embedded
  # expressions such as '#(userId)' inside docstrings.
  var definitions: dict<number> = {}
  var def_pattern = '^\s*\*\s*def\s\+\([a-zA-Z0-9_]\+\)'
  for i in range(len(lines))
    if has_key(docstring_body, string(i + 1))
      continue
    endif
    var m = matchlist(lines[i], def_pattern)
    if !empty(m)
      definitions[m[1]] = i + 1
    endif
  endfor

  if empty(definitions)
    return report
  endif

  # Pass 2: usages for ALL definitions in one scan.
  # The original re-scanned every line for every variable, O(lines x vars).
  # matchstrlist() searches once with an alternation of all names and returns
  # every match with its list index. \< \> keep the same word-boundary
  # semantics as the old '\<name\>' test, and \C the case sensitivity.
  var unused = copy(definitions)
  var usage_pattern = '\C\<\%(' .. join(keys(definitions), '\|') .. '\)\>'

  for m in matchstrlist(lines, usage_pattern)
    # A definition line is not a usage of the name it defines (but it may
    # well be a usage of another variable, e.g. '* def b = a + 1').
    if get(definitions, m.text, -1) == m.idx + 1
      continue
    endif
    if has_key(unused, m.text)
      remove(unused, m.text)
      if empty(unused)
        break
      endif
    endif
  endfor

  # Pass 3: report what is left, in line order. Dictionary iteration order is
  # unspecified in Vim, so the original emitted diagnostics - and loclist rows
  # - in an arbitrary order.
  var leftovers = items(unused)
  sort(leftovers, (x, y) => x[1] - y[1])

  var level = RuleLevel('unused_variable')
  for [var_name, lnum] in leftovers
    var [mtext, mstart, mend] = matchstrpos(lines[lnum - 1], '\C\<' .. var_name .. '\>')
    if mstart > -1
      add(report, {
        lnum: lnum,
        col: mstart + 1,
        end_col: mend + 1,
        text: 'Unused variable: ' .. var_name,
        level: level,
      })
    endif
  endfor

  return report
enddef

def LintUndefinedRequestVariables(lines: list<string>,
    docstring_body: dict<bool>): list<dict<any>>
  var report: list<dict<any>> = []
  if !RuleOn('undefined_request_var')
    return report
  endif

  var defined_vars: dict<bool> = {}
  var def_pattern = '^\s*\*\s*def\s\+\([a-zA-Z0-9_]\+\)'
  var request_pattern = '^\s*\(And\|Given\|When\|Then\|\*\)\s\+request\s\+\([a-zA-Z0-9_]\+\)\s*\(#.*\)\?$'
  var level = RuleLevel('undefined_request_var')

  # Both halves parse Karate statements, so docstring payload is skipped: a
  # 'Given request x' line inside a JSON block is text.
  for lnum in range(1, len(lines))
    if has_key(docstring_body, string(lnum))
      continue
    endif
    var line = lines[lnum - 1]

    # Check the 'request' usage FIRST.
    var req_match = matchlist(line, request_pattern)
    if !empty(req_match)
      var var_name = req_match[2]
      if !has_key(defined_vars, var_name)
        var before = matchstr(line, '^\s*\(And\|Given\|When\|Then\|\*\)\s\+request\s\+')
        var col = len(before)
        add(report, {
          lnum: lnum,
          col: col + 1,
          end_col: col + 1 + len(var_name),
          text: "Variable '" .. var_name .. "' used with 'request' is not defined before this line.",
          level: level,
        })
      endif
    endif

    # THEN the definition, so it is available to the following lines.
    var def_match = matchlist(line, def_pattern)
    if !empty(def_match)
      defined_vars[def_match[1]] = true
    endif
  endfor

  return report
enddef


# --- File-level structure ------------------------------------------------

# One pass: a second 'Feature:', a 'Background:' in the wrong place or
# repeated, repeated scenario names, and '<placeholder>' left in a plain
# Scenario where nothing will substitute it.
def LintStructure(lines: list<string>, docstring_body: dict<bool>): list<dict<any>>
  var report: list<dict<any>> = []
  var dup_feature = RuleOn('duplicate_feature')
  var background = RuleOn('background_placement')
  var dup_name = RuleOn('duplicate_scenario_name')
  var stray_placeholder = RuleOn('placeholder_outside_outline')
  if !dup_feature && !background && !dup_name && !stray_placeholder
    return report
  endif

  var feature_seen = false
  var background_lnum = 0
  var scenario_seen = false
  var in_plain_scenario = false
  var names: dict<number> = {}
  var lnum = 0

  for line in lines
    lnum += 1
    if has_key(docstring_body, string(lnum))
      continue
    endif

    if line =~# '\C^\s*Feature:'
      in_plain_scenario = false
      if feature_seen && dup_feature
        AddLineDiag(report, lines, lnum,
          "Duplicate 'Feature:' block; a feature file declares exactly one",
          RuleLevel('duplicate_feature'))
      endif
      feature_seen = true
      continue
    endif

    if line =~# '\C^\s*Background:'
      in_plain_scenario = false
      if background
        if background_lnum > 0
          AddLineDiag(report, lines, lnum,
            printf("Duplicate 'Background:' block (the first one is on line %d)", background_lnum),
            RuleLevel('background_placement'))
        elseif scenario_seen
          AddLineDiag(report, lines, lnum,
            "'Background:' must come before the first 'Scenario:'",
            RuleLevel('background_placement'))
        endif
      endif
      if background_lnum == 0
        background_lnum = lnum
      endif
      continue
    endif

    if line =~# '\C^\s*@'
      in_plain_scenario = false
      continue
    endif

    var title = matchlist(line, '\C^\s*Scenario\%( Outline\)\?:\s*\(.\{-}\)\s*$')
    if !empty(title)
      scenario_seen = true
      in_plain_scenario = line !~# '\C^\s*Scenario Outline:'

      if dup_name && !empty(title[1])
        if has_key(names, title[1])
          AddLineDiag(report, lines, lnum,
            printf("Duplicate scenario name '%s' (first used on line %d)", title[1], names[title[1]]),
            RuleLevel('duplicate_scenario_name'))
        else
          names[title[1]] = lnum
        endif
      endif
      continue
    endif

    # A '<name>' in a plain Scenario is never substituted - it is almost
    # always a step copied out of a Scenario Outline.
    #
    # Only identifier-shaped names count, and a line carrying '</' or '/>' is
    # left alone: Karate allows inline XML such as
    # '* def body = <root>text</root>', whose tags are not placeholders.
    if stray_placeholder && in_plain_scenario && line =~# STEP_PATTERN
        && stridx(line, '<') >= 0
        && stridx(line, '</') < 0 && stridx(line, '/>') < 0
      var level = RuleLevel('placeholder_outside_outline')
      var start = 0
      while true
        var [text, from, to] = matchstrpos(line, '<[A-Za-z_][A-Za-z0-9_]*>', start)
        if from < 0
          break
        endif
        add(report, {
          lnum: lnum, col: from + 1, end_col: to + 1,
          text: printf("Placeholder '%s' in a plain Scenario is never substituted; use 'Scenario Outline'", text),
          level: level,
        })
        start = to
      endwhile
    endif
  endfor

  return report
enddef


# --- The report ----------------------------------------------------------

export def GenerateReport(): list<dict<any>>
  var report: list<dict<any>> = []
  # Read the buffer exactly once; every rule below works off this list.
  var buffer_lines = getline(1, '$')

  # Resolve rule toggles and levels once instead of per line.
  var active_rules: list<dict<any>> = []
  for rule in SIMPLE_LINE_RULES
    if RuleOn(rule.name)
      add(active_rules, {
        pattern: rule.pattern,
        line_pattern: get(rule, 'line_pattern', rule.pattern),
        text: rule.text,
        in_docstring: get(rule, 'in_docstring', false),
        level: RuleLevel(rule.name),
      })
    endif
  endfor

  var max_len = g:karate_linter_max_line_length
  var max_len_level = RuleLevel('max_line_length')

  # This loop doubles as the single source of truth for docstring regions.
  # Tracking the state here is free - the loop already visits every line - and
  # every later rule reuses the map instead of re-scanning the buffer.
  #
  # The '"""' delimiters themselves count as Karate syntax, not as body, so
  # trailing whitespace on a delimiter line is still reported.
  var docstring_body: dict<bool> = {}
  var in_docstring = false
  var docstring_start = 0

  var lnum = 0
  for line in buffer_lines
    lnum += 1

    var is_body = false
    if stridx(line, '"""') >= 0 && line =~# DOCSTRING_PATTERN
      in_docstring = !in_docstring
      docstring_start = in_docstring ? lnum : 0
    elseif in_docstring
      is_body = true
      docstring_body[string(lnum)] = true
    endif

    for rule in active_rules
      if is_body && !rule.in_docstring
        continue
      endif
      if line =~# rule.line_pattern
        # matchstrpos() gives position and length in one regex pass; this was
        # =~# plus match() plus matchstr(), i.e. three passes.
        var [mtext, mstart, mend] = matchstrpos(line, rule.pattern)
        if mstart > -1
          add(report, {
            lnum: lnum, col: mstart + 1, end_col: mend + 1,
            text: rule.text, level: rule.level,
          })
        endif
      endif
    endfor

    # Max line length, measured in display columns - what the user actually
    # sees. It used to count bytes, which halved the effective limit for any
    # non-ASCII text: a Cyrillic step 83 columns wide was reported as 143.
    #
    # Skipped inside docstrings: a long JSON line usually cannot be wrapped
    # without changing the payload being sent.
    #
    # strdisplaywidth() is only paid for on lines that could possibly be over
    # the limit. Without tabs a character never occupies more cells than it
    # takes bytes, so len() is a sound upper bound; a tab breaks that, hence
    # the second test.
    if !is_body && max_len > 0 && (len(line) > max_len || stridx(line, "\t") >= 0)
      var width = strdisplaywidth(line)
      if width > max_len
        add(report, {
          lnum: lnum,
          col: ColumnBeyondWidth(line, max_len) + 1,
          end_col: len(line) + 1,
          text: printf('Line is too long (%d > %d columns)', width, max_len),
          level: max_len_level,
        })
      endif
    endif
  endfor

  extend(report, FindUnusedVariables(buffer_lines, docstring_body))
  extend(report, LintDelimiters(buffer_lines, docstring_body))

  if RuleOn('missing_examples') || RuleOn('orphaned_examples')
    var outline_scan = ScanOutlines(buffer_lines, docstring_body)

    if RuleOn('missing_examples')
      var level = RuleLevel('missing_examples')
      for invalid in outline_scan.invalid
        AddLineDiag(report, buffer_lines, invalid,
          "'Scenario Outline' without a corresponding 'Examples' block", level)
      endfor
    endif

    if RuleOn('orphaned_examples')
      var level = RuleLevel('orphaned_examples')
      for orphan in outline_scan.orphaned
        AddLineDiag(report, buffer_lines, orphan,
          "Found 'orphaned' 'Examples' block without 'Scenario Outline'", level)
      endfor
    endif
  endif

  # Derived from the docstring state tracked above: the block is unclosed only
  # when its closing '"""' never turned up before EOF. The old code guessed -
  # it declared the block unclosed as soon as a line inside it looked like a
  # step, which fires on perfectly valid JSON and JS payloads.
  if RuleOn('unclosed_docstring') && in_docstring && docstring_start > 0
    AddLineDiag(report, buffer_lines, docstring_start,
      'Unclosed DocString. Block started here.', RuleLevel('unclosed_docstring'))
  endif

  if RuleOn('undefined_placeholder') || RuleOn('unused_header') || RuleOn('examples_table')
    extend(report, LintScenarioOutlines(buffer_lines, docstring_body))
  endif

  extend(report, LintUndefinedRequestVariables(buffer_lines, docstring_body))
  extend(report, LintStructure(buffer_lines, docstring_body))

  # File-level rules. match() on a List stops at the first hit and makes no
  # copy, unlike the filter(copy(...)) this replaced, which scanned the whole
  # buffer six times.
  if RuleOn('missing_feature') || RuleOn('missing_scenario') || RuleOn('missing_background')
    var anchor = FirstContentLine(buffer_lines)
    var has_feature = HasLineOutsideDocstring(buffer_lines, '^\s*Feature:', docstring_body)
    var has_scenario = HasLineOutsideDocstring(buffer_lines, '^\s*Scenario Outline:', docstring_body)
      || HasLineOutsideDocstring(buffer_lines, '^\s*Scenario:', docstring_body)

    if RuleOn('missing_feature') && !has_feature
      AddLineDiag(report, buffer_lines, anchor,
        "Missing mandatory 'Feature:' block in the file", RuleLevel('missing_feature'))
    endif

    if RuleOn('missing_scenario') && !has_scenario
      AddLineDiag(report, buffer_lines, anchor,
        "Missing 'Scenario:' or 'Scenario Outline:' blocks in the file",
        RuleLevel('missing_scenario'))
    endif

    if RuleOn('missing_background') && has_feature && has_scenario
      if !HasLineOutsideDocstring(buffer_lines, '^\s*Background:', docstring_body)
        AddLineDiag(report, buffer_lines, anchor, "Missing 'Background' block",
          RuleLevel('missing_background'))
      endif
    endif
  endif

  return report
enddef


# --- Rendering -----------------------------------------------------------

def ClearDiagnostics(bufnr: number)
  if bufnr < 0
    return
  endif
  prop_remove({bufnr: bufnr, all: true, type: 'karate_lint_error'})
  prop_remove({bufnr: bufnr, all: true, type: 'karate_lint_warn'})
  sign_unplace('karate_linter_' .. bufnr, {buffer: bufnr})
enddef

export def UpdateDiagnostics()
  var bufnr = bufnr('%')
  ClearDiagnostics(bufnr)

  var report = GenerateReport()

  # Error status for auto-format-on-save.
  b:karate_has_errors = 0
  for issue in report
    if issue.level == ERROR_LEVEL
      b:karate_has_errors = 1
      break
    endif
  endfor

  # Index by line so the cursor handler is a dictionary lookup rather than a
  # scan of the report on every cursor movement.
  var by_line: dict<list<dict<any>>> = {}
  for issue in report
    var key = string(issue.lnum)
    if !has_key(by_line, key)
      by_line[key] = []
    endif
    add(by_line[key], issue)
  endfor
  b:karate_diagnostics = by_line

  # Note: no echoing from here. This also runs from the buffer-load and
  # buffer-write autocommands, where the cursor has not been placed yet and
  # Vim is about to print its own message - a second message on top of that
  # produces a 'Press ENTER' prompt. OnLintTimer() refreshes it instead.

  if empty(report)
    return
  endif

  # Collect first, apply in three calls. prop_add_list() and sign_placelist()
  # replace two function calls per diagnostic, which on a file with a few
  # hundred findings is the whole render.
  #
  # prop_add_list() takes [lnum, col, end_lnum, end_col] with an exclusive
  # end_col - exactly the 'end_col' the rules already produce, since it is
  # col + length.
  var error_ranges: list<list<number>> = []
  var warn_ranges: list<list<number>> = []
  var worst_on_line: dict<bool> = {}

  for issue in report
    # Defence in depth: a rule that computes a bad column must not be able to
    # abort the render for the whole buffer, which is what an E964 out of
    # prop_add() used to do.
    if issue.col < 1 || issue.end_col <= issue.col
      continue
    endif

    var is_error = issue.level == ERROR_LEVEL
    if is_error
      add(error_ranges, [issue.lnum, issue.col, issue.lnum, issue.end_col])
    else
      add(warn_ranges, [issue.lnum, issue.col, issue.lnum, issue.end_col])
    endif

    # A sign id is derived from the line number, so a line with more than one
    # diagnostic only ever gets one sign. Which icon that was used to depend
    # on the order the rules happened to run in, meaning a warning could mask
    # an error; now the worse level always wins.
    var key = string(issue.lnum)
    if is_error || !has_key(worst_on_line, key)
      worst_on_line[key] = is_error
    endif
  endfor

  if !empty(error_ranges)
    prop_add_list({type: 'karate_lint_error', bufnr: bufnr}, error_ranges)
  endif
  if !empty(warn_ranges)
    prop_add_list({type: 'karate_lint_warn', bufnr: bufnr}, warn_ranges)
  endif

  var sign_group = 'karate_linter_' .. bufnr
  var signs: list<dict<any>> = []
  for [key, is_error] in items(worst_on_line)
    var line_number = str2nr(key)
    add(signs, {
      id: SIGN_ID_BASE + line_number,
      group: sign_group,
      name: is_error ? 'KarateLintError' : 'KarateLintWarn',
      buffer: bufnr,
      lnum: line_number,
    })
  endfor
  if !empty(signs)
    sign_placelist(signs)
  endif
enddef


# --- Message for the line under the cursor -------------------------------

# Truncate to a display width. printf('%.<n>S') counts bytes for the
# precision, which cuts multibyte text (a Cyrillic variable name) far too
# early, so the width is measured properly here.
def TruncateToWidth(text: string, maxwidth: number): string
  if maxwidth <= 0
    return ''
  endif
  if strdisplaywidth(text) <= maxwidth
    return text
  endif

  var out = text
  while !empty(out) && strdisplaywidth(out .. '...') > maxwidth
    out = strcharpart(out, 0, strchars(out) - 1)
  endwhile
  return out .. '...'
enddef

# How much room the command line really has. A message that fills the last
# screen line makes Vim prompt with 'Press ENTER', which would be far more
# annoying than a clipped message.
def EchoWidth(): number
  var width = &columns - 1
  if &showcmd
    width -= 11
  endif
  return width
enddef

# Of the diagnostics on a line, the most relevant one: whatever covers the
# cursor column, else errors before warnings, else the leftmost.
def PickDiagnostic(diags: list<dict<any>>, col: number): dict<any>
  var best: dict<any> = {}
  for issue in diags
    if col >= issue.col && col < issue.end_col
      if empty(best) || (issue.level == ERROR_LEVEL && best.level != ERROR_LEVEL)
        best = issue
      endif
    endif
  endfor
  if !empty(best)
    return best
  endif

  for issue in diags
    if empty(best)
        || (issue.level == ERROR_LEVEL && best.level != ERROR_LEVEL)
        || (issue.level == best.level && issue.col < best.col)
      best = issue
    endif
  endfor
  return best
enddef

def FormatDiagnosticMessage(diags: list<dict<any>>, col: number, maxwidth: number): string
  if empty(diags)
    return ''
  endif

  var issue = PickDiagnostic(diags, col)
  var tag = issue.level == ERROR_LEVEL ? 'E' : 'W'
  var extra = len(diags) > 1 ? printf('  (+%d more)', len(diags) - 1) : ''

  # The suffix is kept whole; only the message text is clipped.
  var prefix = '[karate] ' .. tag .. ': '
  var budget = maxwidth - strdisplaywidth(prefix) - strdisplaywidth(extra)
  return prefix .. TruncateToWidth(issue.text, budget) .. extra
enddef

export def EchoDiagnostic()
  if get(g:, 'karate_linter_echo_cursor', 1) == 0
    return
  endif

  # Never write to the command line while inserting or replacing: it fights
  # with the completion menu, and the debounce timer can fire mid-insert.
  if mode() =~# '^[iR]'
    return
  endif

  var diags = get(get(b:, 'karate_diagnostics', {}), string(line('.')), [])
  var message = FormatDiagnosticMessage(diags, col('.'), EchoWidth())

  # Only touch the command line when the message actually changes: echoing on
  # every cursor movement would keep wiping messages from other plugins.
  if message == get(b:, 'karate_echoed', '')
    return
  endif
  b:karate_echoed = message

  if empty(message)
    echo ''
    return
  endif

  var level = PickDiagnostic(diags, col('.')).level
  execute 'echohl' (level == ERROR_LEVEL ? 'ErrorMsg' : 'WarningMsg')
  echo message
  echohl NONE
enddef


# --- Debounced updates ---------------------------------------------------
#
# TextChanged/TextChangedI fire on every keystroke. Re-linting the whole
# buffer that often is pure waste: coalesce bursts of edits into one pass once
# typing pauses.

var lint_timer = -1

export def CancelPendingUpdate()
  if lint_timer != -1
    timer_stop(lint_timer)
    lint_timer = -1
  endif
enddef

def OnLintTimer(target_buf: number, _: number)
  lint_timer = -1
  # The user may have switched buffers while the timer was pending; the new
  # buffer gets its own lint from BufWinEnter, so just drop this one.
  if bufnr('%') != target_buf
    return
  endif
  UpdateDiagnostics()

  # An edit can add or remove a diagnostic on the line the cursor already sits
  # on, and that produces no CursorMoved. This is the one place it is safe to
  # refresh the message: the user is idle, the buffer is loaded, and Vim is
  # not about to print a message of its own.
  EchoDiagnostic()
enddef

export def ScheduleUpdate()
  CancelPendingUpdate()
  var delay = get(g:, 'karate_linter_debounce_ms', 150)
  if delay <= 0
    UpdateDiagnostics()
    return
  endif
  var target_buf = bufnr('%')
  lint_timer = timer_start(delay, (t) => OnLintTimer(target_buf, t))
enddef

# Run any pending lint right now. Needed before anything that reads the cached
# error state, otherwise a debounced edit could still be in flight.
def FlushPendingUpdate()
  CancelPendingUpdate()
  UpdateDiagnostics()
enddef


# --- Commands ------------------------------------------------------------

export def ShowLoclist()
  # The location window itself is a buffer too. Without this guard, running
  # the command a second time while the list has focus lints the list.
  if !empty(&buftype)
    echomsg '[Karate] KarateLintCheck needs a file buffer.'
    return
  endif

  var report = GenerateReport()
  if empty(report)
    # Replace the previous list instead of leaving it behind: its line
    # numbers describe a file that has since been fixed, so jumping from it
    # would land on the wrong lines.
    setloclist(0, [], ' ', {items: [], title: 'Karate lint'})
    lclose
    echomsg '[Karate] No issues found.'
    return
  endif

  # Point at the buffer, not at its name. A name is resolved against the
  # current directory when jumping, so an unnamed buffer - or one opened
  # before a :cd - silently refuses to move; a buffer number always lands.
  var source = bufnr('%')
  var items: list<dict<any>> = []
  for issue in report
    add(items, {
      bufnr: source,
      lnum: issue.lnum,
      col: issue.col,
      text: issue.text,
      type: issue.level == ERROR_LEVEL ? 'E' : 'W',
    })
  endfor

  # The report is assembled rule by rule, so in its natural order the list
  # jumps around the file. Sorted by position it reads top to bottom, and
  # :lnext / :lprevious walk the file in order. sort() is stable, so findings
  # sharing a position keep the order the rules produced them in.
  sort(items, (a, b) => a.lnum == b.lnum ? a.col - b.col : a.lnum - b.lnum)

  # Select the first entry at or after the cursor so the list opens on the
  # problem that was on screen, and <CR> is useful without hunting for it.
  var cursor_lnum = line('.')
  var idx = len(items)
  for i in range(len(items))
    if items[i].lnum >= cursor_lnum
      idx = i + 1
      break
    endif
  endfor

  setloclist(0, [], ' ', {items: items, idx: idx, title: 'Karate lint'})
  lopen
enddef


# --- Auto-formatting on save ---------------------------------------------

def SmartAutoFormat()
  var save_cursor = getcurpos()

  # 1. Store the original content of every docstring block.
  var original_blocks: dict<list<string>> = {}
  for range_pair in FindAllDocstringRanges(getline(1, '$'))
    var start_lnum = range_pair[0]
    var end_lnum = range_pair[1]
    if end_lnum - start_lnum > 1
      original_blocks[string(start_lnum)] = getline(start_lnum + 1, end_lnum - 1)
    else
      original_blocks[string(start_lnum)] = []
    endif
  endfor

  # 2. Format the whole file.
  silent! normal! gg=G

  # 3. Put the original docstring content back, at the new indentation.
  if !empty(original_blocks)
    for key in sort(keys(original_blocks), 'n')
      var start_lnum = str2nr(key)
      var inner_save = getcurpos()
      cursor(start_lnum + 1, 1)
      var end_lnum = search('^\s*"""\s*$', 'W')
      setpos('.', inner_save)

      if end_lnum == 0
        continue
      endif
      if end_lnum - start_lnum > 1
        execute (start_lnum + 1) .. ',' .. (end_lnum - 1) .. 'delete _'
      endif
      append(start_lnum, original_blocks[key])
    endfor
  endif

  setpos('.', save_cursor)
enddef

export def AutoFormatOnSave()
  # Apply any debounced edit before anything reads the cached error state, so
  # the buffer being written is judged as it is right now. Done first and
  # unconditionally: after a save the gutter should be current even when
  # auto-formatting itself is turned off.
  FlushPendingUpdate()

  # If JSON was just formatted, skip this pass so it is not undone.
  if get(b:, 'karate_just_formatted_json', 0) != 0
    b:karate_just_formatted_json = 0
    return
  endif

  if get(g:, 'karate_linter_auto_format_on_save', 1) == 0
    return
  endif
  if get(b:, 'karate_has_errors', 0) != 0
    return
  endif

  SmartAutoFormat()
enddef

export def FormatJsonInDocstring()
  var cursor_lnum = line('.')

  var start_line = search(DOCSTRING_PATTERN, 'bnW')
  if start_line == 0 || start_line > cursor_lnum
    echohl WarningMsg
    echo '[Karate] Cursor is not inside a docstring block.'
    echohl NONE
    return
  endif

  var end_line = search(DOCSTRING_PATTERN, 'nW')
  if end_line == 0 || end_line < cursor_lnum
    echohl WarningMsg
    echo '[Karate] Cursor is not inside a docstring block.'
    echohl NONE
    return
  endif

  if end_line - start_line <= 1
    echomsg '[Karate] Docstring is empty, nothing to format.'
    return
  endif

  var json_input = join(getline(start_line + 1, end_line - 1), "\n")

  var first_char_idx = match(json_input, '\S')
  if first_char_idx == -1
    echomsg '[Karate] Docstring is empty, nothing to format.'
    return
  endif
  var first_char = strpart(json_input, first_char_idx, 1)
  if first_char != '{' && first_char != '['
    echohl WarningMsg
    echo '[Karate] Block does not look like a JSON object or array. Aborting.'
    echohl NONE
    return
  endif

  var indent_str = repeat(' ', indent(start_line))
  var formatted: list<string> = []
  var err = ''

  if executable('jq')
    formatted = systemlist('jq .', json_input)
    if v:shell_error != 0
      err = '[jq] ' .. get(formatted, 0, 'Invalid JSON')
    endif
  elseif executable('python3')
    formatted = systemlist('python3 -m json.tool', json_input)
    if v:shell_error != 0
      err = '[python3] ' .. get(formatted, 0, 'Invalid JSON')
    endif
  elseif executable('python')
    formatted = systemlist('python -m json.tool', json_input)
    if v:shell_error != 0
      err = '[python] ' .. get(formatted, 0, 'Invalid JSON')
    endif
  else
    echohl ErrorMsg
    echo "[Karate] No JSON formatter found. Install 'jq' or Python."
    echohl NONE
    return
  endif

  if !empty(err)
    echohl ErrorMsg
    echo '[Karate] Formatting failed: ' .. err
    echohl NONE
    return
  endif

  execute (start_line + 1) .. ',' .. (end_line - 1) .. 'delete _'
  append(start_line, mapnew(formatted, (_, val) => indent_str .. val))

  # Skip the next auto-format-on-save so it does not undo this.
  b:karate_just_formatted_json = 1
  echomsg '[Karate] Formatted JSON block.'
enddef

export def ReplaceTabsWithSpaces()
  var view = winsaveview()
  var num_spaces = &shiftwidth > 0 ? &shiftwidth : 4

  # :keeppatterns so the substitution does not clobber the search register
  # and the search history.
  silent! keeppatterns execute '%s/\t/' .. repeat(' ', num_spaces) .. '/g'

  winrestview(view)
  echomsg '[Karate] Replaced tabs with spaces.'
enddef

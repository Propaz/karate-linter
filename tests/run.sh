#!/usr/bin/env bash
# Runs the whole suite.
#
#   tests/run.sh            compare the current plugin against tests/baseline.*
#   tests/run.sh --accept   re-record the baseline from the current plugin
#
# The baseline is the contract: any diff means the linter reports something
# different than it did before. Review every diff before accepting it.

set -uo pipefail
cd "$(dirname "$0")/.."

VIM=${VIM:-vim}
status=0

if [[ ${1:-} == --accept ]]; then
    rm -f tests/baseline.raw.txt tests/baseline.sorted.txt
    "$VIM" -Nu NONE -es -S tests/dump_report.vim
    echo "baseline re-recorded:"
    grep -c . tests/baseline.sorted.txt | sed 's/^/  lines: /'
    exit 0
fi

echo "== report snapshot =="
rm -f tests/after.raw.txt tests/after.sorted.txt
KL_OUT=after "$VIM" -Nu NONE -es -S tests/dump_report.vim

if diff -u tests/baseline.sorted.txt tests/after.sorted.txt; then
    echo "  ok   set of diagnostics unchanged"
else
    echo "  FAIL set of diagnostics changed"
    status=1
fi

if ! diff -q tests/baseline.raw.txt tests/after.raw.txt >/dev/null; then
    echo "  note report build order differs (affects loclist order only):"
    diff -u tests/baseline.raw.txt tests/after.raw.txt | sed -n '3,$p' | sed 's/^/        /'
fi

echo
echo "== diagnostics pipeline =="
"$VIM" -Nu NONE -es -S tests/check_diagnostics.vim
sed 's/^/  /' tests/diagnostics.txt
grep -q 'RESULT: ALL OK' tests/diagnostics.txt || status=1

echo
echo "== cursor-line message =="
"$VIM" -Nu NONE -es -S tests/check_echo.vim
sed 's/^/  /' tests/echo.txt
grep -q 'RESULT: ALL OK' tests/echo.txt || status=1

echo
echo "== location list =="
"$VIM" -Nu NONE -es -S tests/check_loclist.vim
sed 's/^/  /' tests/loclist.txt
grep -q 'RESULT: ALL OK' tests/loclist.txt || status=1

echo
echo "== option handling =="
opt_case() {
    local label="$1" expect="$2"; shift 2
    rm -f "$KL_RESULT"
    "$VIM" -Nu NONE -es "$@" -S tests/check_options.vim
    local got; got=$(cat "$KL_RESULT" 2>/dev/null || true)
    unset KL_FIXTURE KL_MATCH
    if [[ "$got" == "$expect" ]]; then
        printf '  ok   %-50s %s\n' "$label" "$got"
    else
        printf '  FAIL %-50s got=%q want=%q\n' "$label" "$got" "$expect"
        status=1
    fi
}
export KL_RESULT=/tmp/karate_linter_opt.$$
opt_case "defaults: rule active, Error"            "6 KarateLintError"
opt_case "new option off"                          "0 -" \
    --cmd 'let g:karate_linter_unbalanced_parens_rule = 0'
opt_case "legacy unclosed_read_rule=0 disables it" "0 -" \
    --cmd 'let g:karate_linter_unclosed_read_rule = 0'
opt_case "legacy level alias honoured"             "6 KarateLintWarn" \
    --cmd "let g:karate_linter_unclosed_read_level = 'KarateLintWarn'"
opt_case "explicit new option beats legacy alias"  "6 KarateLintError" \
    --cmd 'let g:karate_linter_unclosed_read_rule = 0 | let g:karate_linter_unbalanced_parens_rule = 1'

export KL_FIXTURE=24_delimiters_bad.feature KL_MATCH="Unclosed '"
opt_case "brackets: all three kinds reported"     "6 KarateLintError"
export KL_FIXTURE=24_delimiters_bad.feature KL_MATCH="Unclosed '"
opt_case "brackets: rule off"                     "0 -" \
    --cmd 'let g:karate_linter_unbalanced_parens_rule = 0'

export KL_FIXTURE=24_delimiters_bad.feature KL_MATCH='Unterminated string'
opt_case "unterminated string reported"           "1 KarateLintError"
export KL_FIXTURE=24_delimiters_bad.feature KL_MATCH='Unterminated string'
opt_case "unterminated string: rule off"          "0 -" \
    --cmd 'let g:karate_linter_unterminated_string_rule = 0'

export KL_FIXTURE=26_examples_table.feature KL_MATCH='Examples \(row\|table\)\|Duplicate Examples'
opt_case "examples table findings"                "4 KarateLintError"
export KL_FIXTURE=26_examples_table.feature KL_MATCH='Examples \(row\|table\)\|Duplicate Examples'
opt_case "examples table: rule off"               "0 -" \
    --cmd 'let g:karate_linter_examples_table_rule = 0'

export KL_FIXTURE=27_structure_bad.feature KL_MATCH="Duplicate 'Feature:'"
opt_case "duplicate Feature reported"             "1 KarateLintError"
export KL_FIXTURE=27_structure_bad.feature KL_MATCH="Duplicate 'Feature:'"
opt_case "duplicate Feature: rule off"            "0 -"     --cmd 'let g:karate_linter_duplicate_feature_rule = 0'

export KL_FIXTURE=29_background_after_scenario.feature KL_MATCH="must come before"
opt_case "background placement reported"          "1 KarateLintError"
export KL_FIXTURE=29_background_after_scenario.feature KL_MATCH="must come before"
opt_case "background placement: rule off"         "0 -"     --cmd 'let g:karate_linter_background_placement_rule = 0'

export KL_FIXTURE=27_structure_bad.feature KL_MATCH="Duplicate scenario name"
opt_case "duplicate scenario name reported"       "1 KarateLintWarn"
export KL_FIXTURE=27_structure_bad.feature KL_MATCH="Duplicate scenario name"
opt_case "duplicate scenario name: rule off"      "0 -"     --cmd 'let g:karate_linter_duplicate_scenario_name_rule = 0'

export KL_FIXTURE=28_placeholder_outside_outline.feature KL_MATCH="never substituted"
opt_case "stray placeholder reported"             "2 KarateLintWarn"
export KL_FIXTURE=28_placeholder_outside_outline.feature KL_MATCH="never substituted"
opt_case "stray placeholder: rule off"            "0 -"     --cmd 'let g:karate_linter_placeholder_outside_outline_rule = 0'

rm -f "$KL_RESULT"

echo
if [[ $status -eq 0 ]]; then
    echo "SUITE OK"
else
    echo "SUITE FAILED"
fi
exit $status

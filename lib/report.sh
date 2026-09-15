#!/bin/sh
# livediag: turn a session's results.tsv into a readable report.txt.
#
# Usage: report.sh SESSION_DIR

dir=${1:-}
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    printf 'usage: report.sh SESSION_DIR\n' >&2
    exit 1
fi

res="$dir/results.tsv"
[ -f "$res" ] || : >"$res"
out="$dir/report.txt"
norm="$dir/.results.norm"

# Guarantee six columns: time, id, status, name, message, category.
awk -F'\t' 'BEGIN { OFS = "\t" } { if (NF < 6) $6 = "Other"; print }' "$res" >"$norm"

TAB=$(printf '\t')

{
    printf 'livediag report\n'
    printf '===============\n'
    printf 'Session:   %s\n' "$dir"
    printf 'Generated: %s\n' "$(date 2>/dev/null)"
    printf '\n'

    if [ -r "$dir/environment.txt" ]; then
        printf 'Environment\n-----------\n'
        sed 's/^/  /' "$dir/environment.txt"
        printf '\n'
    fi

    printf 'Summary\n-------\n'
    awk -F"$TAB" '
        { c[$3]++ }
        END {
            printf "  PASS    %d\n", c["PASS"] + 0
            printf "  FAIL    %d\n", c["FAIL"] + 0
            printf "  WARN    %d\n", c["WARN"] + 0
            printf "  SKIP    %d\n", c["SKIP"] + 0
            printf "  TIMEOUT %d\n", c["TIMEOUT"] + 0
            printf "  --------\n"
            printf "  total   %d\n", NR
        }' "$norm"
    printf '\n'

    printf 'Results by category\n-------------------\n'
    sort -t"$TAB" -k6,6 -k2,2 "$norm" | awk -F"$TAB" '
        {
            if ($6 != cat) {
                cat = $6
                printf "\n[%s]\n", cat
            }
            printf "  %-8s %-22s %s\n", $3, $2, $5
        }'
    printf '\n'

    fails=$(awk -F"$TAB" '$3 == "FAIL" { n++ } END { print n + 0 }' "$norm")
    warns=$(awk -F"$TAB" '$3 == "WARN" { n++ } END { print n + 0 }' "$norm")

    if [ "$fails" -gt 0 ] || [ "$warns" -gt 0 ]; then
        printf 'Needs attention\n---------------\n'
        awk -F"$TAB" '$3 == "FAIL" || $3 == "WARN" {
            printf "  %-8s %-22s %s\n", $3, $2, $5
        }' "$norm"
        printf '\n'
    fi

    printf 'Notes\n-----\n'
    printf '  PASS    the check ran and the subsystem responded as expected\n'
    printf '  FAIL    the subsystem did not work or reported an error\n'
    printf '  WARN    it worked, but something looked wrong or the user reported a problem\n'
    printf '  SKIP    no hardware, no tool, or the user declined the test\n'
    printf '  TIMEOUT the module exceeded its time budget\n'
} >"$out"

rm -f "$norm"
printf '%s\n' "$out"

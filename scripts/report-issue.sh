#!/usr/bin/env bash
# One path for every issue a project files to claude-coordinator (procedures/CORE-FINDINGS.md §2): a
# fixed signature, an existing issue found before a new one, a repeat marked with a reaction (#338).
#   scripts/report-issue.sh signature --source <script or core file> [--step <step>] [--exit <code>] --error <text>
#   scripts/report-issue.sh file --repo <owner/name> --title <title> --body-file <file> --signature <sig>
#                                [--keywords <words>] [--checked <n,n,...>] [--comment-file <file>] [--dry-run]
# signature: one line `<source>: <step>: exit <code>: <words>` - the error text lower-cased (ASCII), URLs,
# dates and times, paths (absolute, with a drive letter, UNC, ~ or ./), hex ids (0x..., or 7+ characters)
# and numbers replaced by the tokens URL, DATE, PATH, ID and N, quotes dropped, whitespace (CR, LF, tabs)
# collapsed, at most 120 characters (bytes): the same error from two machines gives the same line.
# file, in this order: (1) the exact signature (a `Signature: <sig>` line in the body) on a closed issue
# closed as completed -> nothing filed, `FIXED UPSTREAM #<n>` (closed as not planned is no fix: it goes
# on); (2) on an open issue -> a +1 reaction from this account (none added when it is already there), with
# --comment-file that comment too, `REPEAT #<n>`; (3) the keyword search (--keywords, else the title; title
# and body, open and closed, updated in the last 90 days, at most 5): a candidate not in --checked ->
# `CHECK #<a> #<b> ...` and each candidate's title, nothing filed - read them, then run again with them in
# --checked; (4) none left -> the issue filed, its body ending `Checked: #a, #b` (when any) and
# `Signature: <sig>`, `FILED #<n>`. --dry-run prints what it would do and changes nothing. Every gh call is
# read-only but `issue create`, `issue comment` and the reaction.
# Exit codes: 0 a signature, REPEAT, FILED or a dry run of them; 1 usage error or gh failed; 3 FIXED
# UPSTREAM; 4 CHECK. Windows: report-issue.ps1, the same lines and codes.
set -uo pipefail
export LC_ALL=C   # byte-wise and ASCII-only: the same signature under any locale

usage="usage: signature --source <s> [--step <s>] [--exit <code>] --error <text> | file --repo <owner/name> --title <t> --body-file <f> --signature <sig> [--keywords <words>] [--checked <n,n,...>] [--comment-file <f>] [--dry-run]"
mode="${1:-}"; [ $# -gt 0 ] && shift
case "$mode" in signature|file) ;; *) echo "$usage" >&2; exit 1 ;; esac
source="" step="" code="" error="" have_error=0 repo="" title="" body_file="" sig="" keywords="" checked="" comment_file="" dry=0
need() { [ $# -ge 2 ] || { echo "missing value for $1; $usage" >&2; exit 1; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --source) need "$@"; source="$2"; shift 2 ;;
    --step) need "$@"; step="$2"; shift 2 ;;
    --exit) need "$@"; code="$2"; shift 2 ;;
    --error) need "$@"; error="$2"; have_error=1; shift 2 ;;
    --repo) need "$@"; repo="$2"; shift 2 ;;
    --title) need "$@"; title="$2"; shift 2 ;;
    --body-file) need "$@"; body_file="$2"; shift 2 ;;
    --signature) need "$@"; sig="$2"; shift 2 ;;
    --keywords) need "$@"; keywords="$2"; shift 2 ;;
    --checked) need "$@"; checked="$2"; shift 2 ;;
    --comment-file) need "$@"; comment_file="$2"; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) echo "unknown argument: $1; $usage" >&2; exit 1 ;;
  esac
done

# oneline <text>: CR, LF and tabs to spaces, runs of spaces to one, trimmed
oneline() { printf '%s' "$1" | tr '\r\n\t\f\v' '     ' | sed -E 's/ +/ /g; s/^ //; s/ $//'; }

if [ "$mode" = signature ]; then
  [ -n "$source" ] && [ "$have_error" = 1 ] || { echo "signature needs --source and --error; $usage" >&2; exit 1; }
  case "$code" in *[!0-9]*) echo "--exit takes a whole number; $usage" >&2; exit 1 ;; esac
  # the words: lower-cased, quotes dropped, then each kind replaced by its token; a rule that needs the
  # character after a match runs twice, so two matches one character apart are both replaced
  w="$(oneline "$error" | tr 'A-Z' 'a-z' | tr -d "\"'\`" | sed -E '
    s#[a-z][a-z0-9+.-]*://[^ ]*#URL#g
    s#[0-9]{4}[-/][0-9]{2}[-/][0-9]{2}([t ][0-9]{2}:[0-9]{2}(:[0-9]{2}([.,][0-9]+)?)?)?(z|[+-][0-9]{2}:?[0-9]{2})?#DATE#g
    s#(^|[^a-z0-9])[0-9]{1,2}:[0-9]{2}(:[0-9]{2}([.,][0-9]+)?)?#\1DATE#g
    s#(^|[^a-z0-9_.\\-])[a-z]:[\\/][^ ]*#\1PATH#g
    s#(^|[^a-z0-9_.\\-])\\\\[^ ]+#\1PATH#g
    s#(^|[^a-z0-9_.~/\\-])(~|\.{1,2})?/[^ ]+#\1PATH#g
    s#(^|[^a-z0-9])0x[0-9a-f]+#\1ID#g
    s#(^|[^a-z0-9])[0-9a-f]{7,}([^a-z0-9]|$)#\1ID\2#g
    s#(^|[^a-z0-9])[0-9a-f]{7,}([^a-z0-9]|$)#\1ID\2#g
    s#(^|[^a-z0-9])[0-9]+#\1N#g
    s/ +/ /g; s/^ //; s/ $//')"
  line="$(oneline "$source" | tr '\\' '/')"
  [ -n "$step" ] && line="$line: $(oneline "$step")"
  [ -n "$code" ] && line="$line: exit $code"
  [ -n "$w" ] && line="$line: $w"
  # at most 120 bytes: a longer line is cut, the non-ASCII bytes (a cut character's leftover) and the
  # spaces at its new end dropped
  [ "${#line}" -le 120 ] || line="$(printf '%s' "$line" | cut -b 1-120 | sed -E 's/[^ -~]+$//; s/ +$//')"
  printf '%s\n' "$line"
  exit 0
fi

# --- file ---
case "$repo" in */*) ;; *) echo "--repo takes <owner/name>; $usage" >&2; exit 1 ;; esac
[ -n "$title" ] || { echo "file needs --title; $usage" >&2; exit 1; }
[ -f "$body_file" ] || { echo "no such body file: $body_file; $usage" >&2; exit 1; }
[ -z "$comment_file" ] || [ -f "$comment_file" ] || { echo "no such comment file: $comment_file; $usage" >&2; exit 1; }
sig="$(oneline "$sig")"
[ -n "$sig" ] || { echo "file needs --signature; $usage" >&2; exit 1; }
nums=""   # the --checked numbers, "#" and spaces allowed, in their order, each once
for n in $(printf '%s' "$checked" | tr ',#' '  '); do
  case "$n" in *[!0-9]*) echo "--checked takes issue numbers: $checked; $usage" >&2; exit 1 ;; esac
  case " $nums " in *" $n "*) ;; *) nums="${nums:+$nums }$n" ;; esac
done
command -v gh >/dev/null 2>&1 || { echo "gh: command not found" >&2; exit 1; }
tmp="$(mktemp -d)" || exit 1; trap 'rm -rf "$tmp"' EXIT

# q <gh args>: gh's output; a failed gh stops the run (exit 1), called as `x="$(q ...)" || exit 1`
q() { local out; out="$(gh "$@" 2>"$tmp/err")" || { printf 'gh %s %s failed: %s\n' "$1" "$2" "$(cat "$tmp/err")" >&2; return 1; }; printf '%s\n' "$out"; }
# jstr <text>: a JSON string literal
jstr() { printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; }
ROW='[.number, .state, .stateReason, .title] | @tsv'

# (1) and (2): the exact phrase finds the candidates, a body line equal to `Signature: <sig>` decides
phrase="$(printf '%s' "$sig" | tr -d '"')"
exact="$(q issue list --repo "$repo" --state all --search "\"$phrase\" in:body" --json number,state,stateReason,title,body --limit 20 \
  --jq ".[] | select(any((.body // \"\") | split(\"\\n\")[]; rtrimstr(\"\\r\") | rtrimstr(\" \") == $(jstr "Signature: $sig"))) | $ROW")" || exit 1
TAB="$(printf '\t')"
open="" fixed=""
while IFS="$TAB" read -r n st why t; do
  [ -n "$n" ] || continue
  case "$st" in
    OPEN) [ -n "$open" ] || open="$n$TAB$t" ;;
    CLOSED) [ "$why" = COMPLETED ] && [ -z "$fixed" ] && fixed="$n$TAB$t" ;;
  esac
done <<EOF
$exact
EOF

if [ -n "$fixed" ]; then
  printf 'FIXED UPSTREAM #%s: %s\n' "${fixed%%"$TAB"*}" "${fixed#*"$TAB"}"
  exit 3
fi
if [ -n "$open" ]; then
  n="${open%%"$TAB"*}" t="${open#*"$TAB"}"
  login="$(q api user --jq .login)" || exit 1
  mine="$(q api "repos/$repo/issues/$n/reactions?per_page=100" --paginate --jq '.[] | [.content, .user.login] | @tsv')" || exit 1
  react=1; printf '%s\n' "$mine" | grep -qxF -- "+1$TAB$login" && react=0
  if [ "$dry" = 1 ]; then
    todo=""; [ "$react" = 1 ] && todo="a +1 reaction"
    [ -n "$comment_file" ] && todo="${todo:+$todo and }the comment from $comment_file"
    printf 'REPEAT #%s: %s (dry run: %s)\n' "$n" "$t" "${todo:+would add $todo}${todo:-nothing to add}"
    exit 0
  fi
  if [ "$react" = 1 ]; then q api --method POST "repos/$repo/issues/$n/reactions" -f content=+1 >/dev/null || exit 1; fi
  if [ -n "$comment_file" ]; then q issue comment "$n" --repo "$repo" --body-file "$comment_file" >/dev/null || exit 1; fi
  printf 'REPEAT #%s: %s\n' "$n" "$t"
  exit 0
fi

# (3): the keyword search over the last 90 days; candidates not read yet stop the filing
now="$(date -u +%s)"; t0=$((now - 90 * 86400))
since="$(date -u -d "@$t0" +%Y-%m-%d 2>/dev/null || date -u -r "$t0" +%Y-%m-%d)"
words="$(oneline "${keywords:-$title}" | tr -d '"')"
cands="$(q issue list --repo "$repo" --state all --search "$words in:title,body updated:>=$since" --json number,state,stateReason,title --limit 5 --jq ".[] | $ROW")" || exit 1
new="" lines=""
while IFS="$TAB" read -r n st why t; do
  [ -n "$n" ] || continue
  case " $nums " in *" $n "*) continue ;; esac
  new="$new #$n"; lines="$lines#$n $st${why:+ $why}: $t
"
done <<EOF
$cands
EOF
if [ -n "$new" ]; then
  all="$nums"; for n in $new; do all="${all:+$all,}${n#\#}"; done
  printf 'CHECK%s\n%s' "$new" "$lines"
  printf 'read each: the same problem -> a +1 reaction there (gh api --method POST repos/%s/issues/<n>/reactions -f content=+1), a comment only with something new; none -> run again with --checked %s\n' "$repo" "$(printf '%s' "$all" | tr ' ' ',')"
  exit 4
fi

# (4): file it, the body's own Signature and Checked lines replaced by the script's
{ tr -d '\r' < "$body_file" | grep -vE '^(Signature|Checked):' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
  printf '\n'
  [ -n "$nums" ] && printf 'Checked: #%s\n' "$(printf '%s' "$nums" | sed 's/ /, #/g')"
  printf 'Signature: %s\n' "$sig"; } > "$tmp/body.md"
if [ "$dry" = 1 ]; then
  printf 'WOULD FILE in %s (dry run): %s\n' "$repo" "$title"
  sed -n '/^Checked:/p; /^Signature:/p' "$tmp/body.md"
  exit 0
fi
url="$(q issue create --repo "$repo" --title "$title" --body-file "$tmp/body.md")" || exit 1
n="$(printf '%s\n' "$url" | sed -n 's|.*/issues/\([0-9][0-9]*\).*|\1|p' | tail -n 1)"
printf 'FILED #%s: %s\n' "${n:-?}" "$title"
exit 0

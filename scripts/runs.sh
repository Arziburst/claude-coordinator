#!/usr/bin/env bash
# A run's row in the run log, and the finished runs that have none (#332; macOS / Linux, no dependencies;
# Windows: runs.ps1 - the same output and exit codes).
#   scripts/runs.sh add --log <RUNS.tsv> --session <id> --task <n> --role <role> --kind <kind> --model <m>
#                   --effort <e> --estimate <cost|-> --estimate-time <t|-> --result <word> [--date <YYYY-MM-DD>]
#   scripts/runs.sh add --log <RUNS.tsv> --in <parent> --tokens <n> --task ... --result <word> [--date ...]
#                   a subagent's row (a tester or verifier run as a subagent): no --session
#   scripts/runs.sh check --log <RUNS.tsv> --root <project root> [--self <session id>] [--since <YYYY-MM-DD>]
# add appends exactly one row (CORE 7) and prints it. Its cells follow the file's header (a first line whose
# fields include `date` and `role`; a column it does not name stays empty, the names it lacks follow in CORE
# 7's order), else CORE 7's order: date task role kind model effort estimate tokens cost result start wall
# active wait estimate_time. tokens, cost, start, wall and active come from `scripts/session-tokens <id>`
# (its total line, its cost line's number, its time line's start= wall= active=), never typed by hand; no
# cost line leaves the cell empty (a note on stderr). An assistant's row (role assistant) gets the cost its
# session spent since that assistant's previous row: the session's cost less the earlier rows' of the same
# task column (its name) and the same start (CORE 7). With --in: tokens = --tokens, cost `in <parent>`,
# start, wall and active empty. wait stays empty (task rows: run-stats --task ... --append); date: --date,
# else today (UTC). Result words: approved done pass `rework <n>` escalated failed dropped (stopped without a
# result) ready. The file keeps its BOM and its line ends (a CRLF file gets a CRLF row); a last line
# without its end gets one first. Refused, the file unchanged: another result word or a cell with a tab or
# a line break (exit 2); no transcript for --session (exit 1); a run log that is no file or cannot be read
# or written (exit 1, a line `runs:`, no row printed); a row already there with the same start and role
# (exit 1) - except role assistant, whose rows share their session's start.
# check lists the project's finished sessions (`claude agents --json --all`: the process ended - state
# done, stopped or failed and no status field; a status idle, a worker waiting between rounds, or busy is
# not finished: its row is written when it is stopped) whose start has no row: one line
# `MISSING <short id> <name> <start>` each, else
# `ALL LOGGED`. A session is the project's when its folder is the root or inside it, or a root of the
# root's repository's worktrees (`git worktree list`) or inside one, compared as paths (CORE 1.17). Never
# listed: --self (by its session id or short id; the coordinator's own runs get a row per day), a name
# starting `assistant:` (rows per day, CORE 7), a session without a transcript (no row can be written).
# Its start: the session-tokens time line's start=; logged = a row's start cell equals it. --since: only
# sessions started on that date or later. check only reads - a log it cannot read is exit 1, never read
# as empty: it writes only its own temp folder (claude's output, removed at its end), touches no
# session, and runs nothing but claude agents --json --all, git worktree list and session-tokens.
# Exit 0 (check: also when it lists some), 1 as above or when claude agents fails, 2 on a usage error.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
usage() { sed -n '2,36s/^# \{0,1\}//p' "$0" >&2; exit 2; }
die() { echo "runs: $2" >&2; exit "$1"; }
[ $# -ge 1 ] || usage
cmd="$1"; shift
case "$cmd" in add|check) ;; *) usage ;; esac
log="" session="" task="" role="" kind="" model="" effort="" est="" estt="" result="" date="" in="" tokens=""
root="" self="" since=""
seen=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --log) log="$2" ;; --session) session="$2" ;; --task) task="$2" ;; --role) role="$2" ;; --kind) kind="$2" ;;
    --model) model="$2" ;; --effort) effort="$2" ;; --estimate) est="$2" ;; --estimate-time) estt="$2" ;;
    --result) result="$2" ;; --date) date="$2" ;; --in) in="$2" ;; --tokens) tokens="$2" ;;
    --root) root="$2" ;; --self) self="$2" ;; --since) since="$2" ;;
    *) usage ;;
  esac
  seen="$seen $1"; shift 2
done
[ -n "$log" ] || usage
TAB="$(printf '\t')"; CR="$(printf '\r')"
NAMES="date task role kind model effort estimate tokens cost result start wall active wait estimate_time"
# plain <file>: its lines without the BOM and the CRs (bytes as they are: C locale, a BOM is three bytes)
plain() { LC_ALL=C awk '{ if (NR == 1 && substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4); sub(/\r$/, ""); print }' "$1"; }
# header <file>: the header's names, one per line, when its first line is one; else none
header() { plain "$1" | LC_ALL=C awk -F'\t' '
  NR == 1 { h = 0; for (i = 1; i <= NF; i++) if ($i == "date" || $i == "role") h++
    if (h >= 2) for (i = 1; i <= NF; i++) print $i; exit }'; }
# cols <file>: the column names in the file's order (its header, else CORE 7's), space-separated
cols() { local h; h="$(header "$1")"; if [ -n "$h" ]; then printf '%s\n' "$h" | tr '\n' ' '; else printf '%s' "$NAMES"; fi; }
# rowsof <file>: the data rows as they are (the header, comments and empty lines left out)
rowsof() { plain "$1" | LC_ALL=C awk -F'\t' '
  NR == 1 { h = 0; for (i = 1; i <= NF; i++) if ($i == "date" || $i == "role") h++; if (h >= 2) next }
  /^#/ || /^$/ { next } { print }'; }
# canread <file>: a file that can be read, else exit 1 (a directory, a missing file, one held open without
# sharing: never read as empty)
canread() { [ -f "$1" ] || die 1 "no run log at $1 (no such file)"
  { : < "$1"; } 2>/dev/null && cat "$1" > /dev/null 2>&1 || die 1 "cannot read the run log $1"; }
# colno <cols> <name>: its field number, 0 when absent
colno() { printf '%s\n' "$1" | tr ' ' '\n' | awk -v n="$2" 'NF { i++; if ($0 == n) { print i; f = 1; exit } } END { if (!f) print 0 }'; }

if [ "$cmd" = add ]; then
  for o in $seen; do case "$o" in --root|--self|--since) usage ;; esac; done
  [ -n "$task" ] && [ -n "$role" ] && [ -n "$kind" ] && [ -n "$model" ] && [ -n "$effort" ] && [ -n "$est" ] &&
    [ -n "$estt" ] && [ -n "$result" ] || usage
  if [ -n "$session" ]; then [ -z "$in$tokens" ] || usage
  else [ -n "$in" ] && [ -n "$tokens" ] || usage
       printf '%s' "$tokens" | grep -Eq '^[0-9]+$' || die 2 "--tokens must be a number: $tokens"; fi
  printf '%s\n' "$result" | grep -Eqx 'approved|done|pass|rework [0-9]+|escalated|failed|dropped|ready' ||
    die 2 "result '$result' is not one of: approved done pass 'rework <n>' escalated failed dropped ready"
  [ -n "$date" ] || date="$(date -u +%Y-%m-%d)"
  printf '%s\n' "$date" | grep -Eqx '[0-9]{4}-[0-9]{2}-[0-9]{2}' || die 2 "--date must be YYYY-MM-DD: $date"
  for v in "$task" "$role" "$kind" "$model" "$effort" "$est" "$estt" "$date" "$in" "$session"; do
    case "$v" in *"$TAB"*|*"$CR"*|*'
'*) die 2 "a cell may not hold a tab or a line break" ;; esac
  done
  canread "$log"
  # opened for appending, nothing written: a read-only file or one held open without sharing fails here
  { : >> "$log"; } 2>/dev/null && [ -w "$log" ] || die 1 "cannot write the run log $log"
  cost="" start="" wall="" active=""
  if [ -n "$session" ]; then
    st="$(bash "$here/session-tokens.sh" "$session" | tr -d '\r')" || die 1 "no transcript for session $session (session-tokens failed)"
    tokens="$(printf '%s\n' "$st" | awk '$1 == "total" { print $2; exit }')"
    tl="$(printf '%s\n' "$st" | awk '$1 == "time" { print; exit }')"
    [ -n "$tokens" ] && [ -n "$tl" ] || die 1 "no transcript for session $session (no total or time line)"
    cost="$(printf '%s\n' "$st" | awk '$1 == "cost" { v = $2; sub(/^\$/, "", v); print v; exit }')"
    kv() { printf '%s\n' "$tl" | awk -v w="$1" '{ for (i = 2; i <= NF; i++) { n = index($i, "="); if (substr($i, 1, n - 1) == w) { v = substr($i, n + 1); sub(/m$/, "", v); print v } } }'; }
    start="$(kv start)"; wall="$(kv wall)"; active="$(kv active)"
    c="$(cols "$log")"; ns="$(colno "$c" start)"; nr="$(colno "$c" role)"; nc="$(colno "$c" cost)"; nt="$(colno "$c" task)"
    if [ "$role" != assistant ]; then
      [ "$ns" -gt 0 ] && [ "$nr" -gt 0 ] && rowsof "$log" | awk -F'\t' -v s="$ns" -v r="$nr" -v S="$start" -v R="$role" \
        '$s == S && $r == R { f = 1 } END { exit !f }' &&
        die 1 "a row for session start $start and role $role is already in $log"
    elif [ -n "$cost" ] && [ "$ns" -gt 0 ] && [ "$nc" -gt 0 ] && [ "$nt" -gt 0 ]; then
      # the cost since this assistant's previous row: less the earlier rows' of its name and this start
      cost="$(rowsof "$log" | awk -F'\t' -v s="$ns" -v r="$nr" -v c="$nc" -v t="$nt" -v S="$start" -v T="$task" -v C="$cost" '
        $s == S && $t == T && $r == "assistant" { v = $c; if (match(v, /^\$?[0-9]+(\.[0-9]+)?/)) { v = substr(v, RSTART, RLENGTH); sub(/^\$/, "", v); p += v } }
        END { x = C - p; if (x < 0) x = 0; printf "%.4f\n", x + 1e-12 }')"
    fi
    [ -n "$cost" ] || echo "runs: session-tokens printed no cost line for $session; the cost cell is left empty" >&2
  else
    cost="in $in"
  fi
  c="$(cols "$log")"
  row="$(printf '%s\n' "date=$date" "task=$task" "role=$role" "kind=$kind" "model=$model" "effort=$effort" "estimate=$est" \
    "tokens=$tokens" "cost=$cost" "result=$result" "start=$start" "wall=$wall" "active=$active" "wait=" "estimate_time=$estt" |
    LC_ALL=C awk -v hd="$c" -v nn="$NAMES" '
    { i = index($0, "="); V[substr($0, 1, i - 1)] = substr($0, i + 1) }
    END { nh = split(hd, h, " "); m = split(nn, d, " "); o = ""
      for (i = 1; i <= nh; i++) { v = ""; if ((h[i] in V) && !(h[i] in u)) { v = V[h[i]]; u[h[i]] = 1 }; o = o (i > 1 ? "\t" : "") v }
      for (i = 1; i <= m; i++) if (!(d[i] in u)) o = o (o == "" && nh == 0 ? "" : "\t") V[d[i]]
      print o }')"
  nl='
'; [ "$(tr -cd '\r' < "$log" | wc -c | tr -d ' ')" = 0 ] || nl="$CR$nl"   # not grep: Git Bash's drops CRs
  pre=""; if [ -s "$log" ] && [ "$(tail -c 1 "$log" | wc -l | tr -d ' ')" = 0 ]; then pre="$nl"; fi
  { printf '%s%s%s' "$pre" "$row" "$nl" >> "$log"; } 2>/dev/null || die 1 "cannot write the run log $log"
  printf '%s\n' "$row"
  exit 0
fi

# check
for o in $seen; do case "$o" in --log|--root|--self|--since) ;; *) usage ;; esac; done
[ -n "$root" ] || usage
[ -z "$since" ] || printf '%s\n' "$since" | grep -Eqx '[0-9]{4}-[0-9]{2}-[0-9]{2}' || die 2 "--since must be YYYY-MM-DD: $since"
canread "$log"
# canon <path>: the path to compare - its real folder when it exists, forward slashes, no trailing slash,
# a drive letter in lower case (C:\x and C:/x the same)
canon() { local p="$1" r
  if [ -d "$p" ] && r="$(cd "$p" 2>/dev/null && pwd -P)"; then p="$r"
    command -v cygpath >/dev/null 2>&1 && p="$(cygpath -m "$p")"; fi
  printf '%s\n' "$p" | sed 's|\\|/|g; s|/*$||' | awk '{ if ($0 ~ /^[A-Za-z]:/) $0 = tolower(substr($0, 1, 1)) substr($0, 2); print }'; }
roots="$(canon "$root")"
wl="$(git -C "$root" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p')"
while IFS= read -r w; do [ -n "$w" ] && roots="$roots
$(canon "$w")"; done <<EOF
$wl
EOF
tdir="$(mktemp -d "${TMPDIR:-/tmp}/runs.XXXXXX")" || die 1 "no temp folder for claude's output"
trap 'rm -f "$tdir/out" "$tdir/err"; rmdir "$tdir" 2>/dev/null' EXIT
claude agents --json --all > "$tdir/out" 2> "$tdir/err" < /dev/null; rc=$?
if [ "$rc" != 0 ] || ! grep -q '\[' "$tdir/out"; then
  e="$(sed -n '/./{p;q;}' "$tdir/err")"; die 1 "claude agents --json --all failed (exit $rc)${e:+: $e}"
fi
# the finished sessions: `<id> TAB <sessionId> TAB <cwd> TAB <name>` (string values unescaped as
# watch-sessions.sh does)
fin="$(LC_ALL=C awk 'BEGIN { RS = "\001" } { s = s $0 } END {
    n = length(s); d = 0; q = 0; after = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1)
      if (q) {
        if (c == "\\") { c = substr(s, ++i, 1)
          if (c == "n" || c == "r" || c == "t" || c == "b" || c == "f") c = " "; else if (c == "u") c = "\\u" }
        else if (c == "\"") { q = 0
          if (d == 2) { if (after) { v[k] = t; after = 0 } else k = t }
          continue }
        t = t c; continue
      }
      if (c == "\"") { q = 1; t = "" }
      else if (c == ":") { if (d == 2) after = 1 }
      else if (c == ",") { if (d == 2) after = 0 }
      else if (c == "{" || c == "[") { if (d == 2) after = 0; d++ }
      else if (c == "}" || c == "]") {
        if (d == 2 && c == "}" && v["id"] != "") {
          st = v["state"]   # never v["status"] here: reading it would create the key
          if ((st == "done" || st == "stopped" || st == "failed") && !("status" in v))
            print v["id"] "\t" v["sessionId"] "\t" v["cwd"] "\t" v["name"]
        }
        if (d == 2) delete v
        d--
      }
    } }' "$tdir/out")"
starts="$(rowsof "$log" | awk -F'\t' -v s="$(colno "$(cols "$log")" start)" 's > 0 && $s != "" { print $s }')"
missing=""
while IFS="$TAB" read -r id sid cwd name; do
  [ -n "$id" ] || continue
  [ -n "$self" ] && { [ "$self" = "$id" ] || [ "$self" = "$sid" ]; } && continue
  case "$name" in assistant:*) continue ;; esac
  p="$(canon "$cwd")"; inside=0
  while IFS= read -r r; do [ -n "$r" ] || continue
    case "$p" in "$r"|"$r"/*) inside=1; break ;; esac
    if [ "${r#[a-z]:}" != "$r" ]; then   # a Windows path: no case
      lp="$(printf '%s' "$p" | tr A-Z a-z)"; lr="$(printf '%s' "$r" | tr A-Z a-z)"
      case "$lp" in "$lr"|"$lr"/*) inside=1; break ;; esac
    fi
  done <<EOF
$roots
EOF
  [ "$inside" = 1 ] || continue
  start="$(bash "$here/session-tokens.sh" "${sid:-$id}" 2>/dev/null | tr -d '\r' |
    awk '$1 == "time" { for (i = 2; i <= NF; i++) if (substr($i, 1, 6) == "start=") print substr($i, 7) }')"
  [ -n "$start" ] || continue
  [ -z "$since" ] || [ ! "${start%%T*}" \< "$since" ] || continue
  printf '%s\n' "$starts" | grep -qxF -- "$start" && continue
  missing="$missing
MISSING $id $name $start"
done <<EOF
$fin
EOF
if [ -n "$missing" ]; then printf '%s\n' "$missing" | sed '/^$/d'; else echo "ALL LOGGED"; fi
exit 0

#!/usr/bin/env bash
# What a Claude Code session used (macOS / Linux, no dependencies; Windows: session-tokens.ps1).
#   scripts/session-tokens.sh <session-id | id prefix | transcript.jsonl>
#   scripts/session-tokens.sh --since <UTC time, e.g. 2026-10-05T17:00:00Z>   every session on the account
#                             (all projects: the limits are per account), messages from that time on
#   scripts/session-tokens.sh --prune     delete status files older than 7 days (other projects' too)
# Prints lines for RUNS.tsv (CORE §7):
#   <model>  <total>  in=<n> out>=<n> cache_read=<n> cache_write=<n>   — per model, summed from the
#            transcripts and their subagents, each message once; input and cache counts are exact,
#            output is a LOWER BOUND (the transcript stores the count from before a message finished)
#   total    <total>  in=… out>=… cache_read=… cache_write=…          — all models together
#   cost     $<usd>   — one session only: the CLI's own cumulative cost at list price, from the status
#            line's per-session file ~/.claude/coordinator/sessions/<id>.json; absent if never drawn
# The status file's token fields are the LAST request's usage, not the session's, so they are ignored.
# Exit 1 when nothing is found or a prefix is ambiguous. Reads the JSON as text, no parser needed.
set -eu
[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,15s/^# \{0,1\}//p' "$0"; exit 2; }
arg="$1"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # Claude Code's own override of ~/.claude
dir="$cfg/coordinator/sessions"
# sums assistant messages from stdin per model, each message id once (its largest output count);
# with SINCE set, only messages whose timestamp is at or after it (compared to the second, UTC)
count() {
  SINCE="${SINCE:-}" awk '
    BEGIN { since = substr(ENVIRON["SINCE"], 1, 19) }
    function num(k,   t) { if (!match(u, "\"" k "\":[ \t]*[0-9]+")) return 0
                           t = substr(u, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", t); return t + 0 }
    /"type":[ \t]*"assistant"/ && /"usage":[ \t]*[{]/ {
      if (since != "") {
        # the record timestamp is the last one (a tool input before it may carry another)
        r = $0; ts = ""
        while (match(r, /"timestamp":[ \t]*"[^"]*"/)) { ts = substr(r, RSTART, RLENGTH); r = substr(r, RSTART + RLENGTH) }
        if (ts == "") next
        sub(/^"timestamp":[ \t]*"/, "", ts)
        if (substr(ts, 1, 19) < since) next
      }
      if (!match($0, /"id":[ \t]*"msg_[^"]*"/)) next
      id = substr($0, RSTART, RLENGTH); sub(/^"id":[ \t]*/, "", id)
      m = "unknown"
      if (match($0, /"model":[ \t]*"[^"]*"/)) { m = substr($0, RSTART, RLENGTH); sub(/^"model":[ \t]*"/, "", m); sub(/"$/, "", m) }
      match($0, /"usage":[ \t]*[{]/); u = substr($0, RSTART)
      o = num("output_tokens")
      if (!(id in out) || o > out[id]) { out[id] = o; mod[id] = m; inp[id] = num("input_tokens")
        rd[id] = num("cache_read_input_tokens"); wr[id] = num("cache_creation_input_tokens") }
    }
    function line(n, i, o, r, w) { return sprintf("%s\t%.0f\tin=%.0f out>=%.0f cache_read=%.0f cache_write=%.0f", n, i + o + r + w, i, o, r, w) }
    END { for (id in out) { m = mod[id]; seen[m] = 1
            MI[m] += inp[id]; MO[m] += out[id]; MR[m] += rd[id]; MW[m] += wr[id]
            I += inp[id]; O += out[id]; R += rd[id]; W += wr[id] }
          for (m in seen) print line(m, MI[m], MO[m], MR[m], MW[m]) | "LC_ALL=C sort"
          close("LC_ALL=C sort")
          print line("total", I, O, R, W) }'
}
case "$arg" in
  --prune)
    [ $# -eq 1 ] || exit 2
    [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -name '*.json' -mtime +7 -print -delete
    exit 0 ;;
  --since)
    [ $# -eq 2 ] || { echo "usage: --since <UTC time, e.g. 2026-10-05T17:00:00Z>" >&2; exit 2; }
    case "$2" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]*) ;;
      *) echo "--since needs YYYY-MM-DDTHH:MM:SS in UTC, got $2" >&2; exit 2 ;; esac
    [ -d "$cfg/projects" ] || { echo "no transcripts in $cfg/projects" >&2; exit 1; }
    find "$cfg/projects" -name '*.jsonl' -type f -exec cat {} + | SINCE="$2" count
    exit 0 ;;
esac
[ $# -eq 1 ] || exit 2
if [ -f "$arg" ]; then main="$arg"; else
  # the full id, else a unique prefix (claude --bg and claude agents print 8 characters)
  main="$(find "$cfg/projects" -maxdepth 2 -name "$arg.jsonl" 2>/dev/null | head -n 1)"
  if [ -z "$main" ]; then
    found="$(find "$cfg/projects" -maxdepth 2 -name "$arg*.jsonl" 2>/dev/null)"
    if [ "$(printf '%s' "$found" | grep -c .)" -gt 1 ]; then
      # ids only: the folder names would show other projects
      echo "ambiguous id $arg:" >&2; printf '%s\n' "$found" | sed 's|.*/||; s|\.jsonl$||' | LC_ALL=C sort >&2; exit 1
    fi
    main="$found"
  fi
fi
if [ -n "$main" ]; then sid="$(basename "$main" .jsonl)"; else
  sid="$(find "$dir" -maxdepth 1 -name "$arg*.json" 2>/dev/null | head -n 1)"
  sid="$(basename "${sid:-$arg}" .json)"
fi
status="$dir/$sid.json"
if [ -n "$main" ] && [ -f "$main" ]; then
  sub="${main%.jsonl}/subagents"
  { cat "$main"; [ -d "$sub" ] && find "$sub" -maxdepth 1 -name '*.jsonl' -exec cat {} + ; true; } | count
elif [ ! -f "$status" ]; then
  echo "no transcript or status file for $arg" >&2; exit 1
fi
if [ -f "$status" ]; then
  awk '{ s = s $0 }
    END { if (match(s, /"total_cost_usd"[ \t]*:[ \t]*[0-9.eE+-]+/)) {
            t = substr(s, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", t); printf "cost\t$%.4f\n", t } }' "$status"
fi

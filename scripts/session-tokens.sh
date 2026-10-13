#!/usr/bin/env bash
# What a Claude Code session used (macOS / Linux, no dependencies; Windows: session-tokens.ps1).
#   scripts/session-tokens.sh <session-id | id prefix | a subagent's agentId | transcript.jsonl>
#   scripts/session-tokens.sh --since <UTC time 2026-10-05T17:00:00Z, or Unix seconds as resets_at>
#                             every session on the account (all projects: the limits are per account)
#   scripts/session-tokens.sh --prune     delete status files older than 7 days (other projects' too)
# Prints lines for RUNS.tsv (CORE §7):
#   <model>  <total>  in=<n> out>=<n> cache_read=<n> cache_write=<n>   — per model, summed from the
#            transcripts and their subagents, each message once; input and cache counts are exact,
#            output is a LOWER BOUND (the transcript stores the count from before a message finished)
#   total    <total>  in=… out>=… cache_read=… cache_write=…          — all models together
#   cost     $<usd>   — one session only: the CLI's own cumulative cost at list price, from the status
#            line's per-session file ~/.claude/coordinator/sessions/<id>.json; absent if never drawn,
#            and for a subagent (its tokens are already counted in its parent session's lines)
# The status file's token fields are the LAST request's usage, not the session's, so they are ignored.
# Exit 1 when nothing is found or a prefix is ambiguous, 2 on a usage error. Reads the JSON as text.
set -eu
[ $# -ge 1 ] && [ $# -le 2 ] || { sed -n '2,16s/^# \{0,1\}//p' "$0"; exit 2; }
arg="$1"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # Claude Code's own override of ~/.claude
dir="$cfg/coordinator/sessions"
# sums assistant messages from stdin per model, each message id once (its largest output count);
# with SINCE set, only messages whose timestamp is at or after it (compared to the second, UTC)
count() {
  SINCE="${SINCE:-}" LC_ALL=C awk '
    BEGIN { since = substr(ENVIRON["SINCE"], 1, 19) }
    function num(k,   t) { if (!match(u, "\"" k "\":[ \t]*[0-9]+")) return 0
                           t = substr(u, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", t); return t + 0 }
    /"type":[ \t]*"assistant"/ && /"usage":[ \t]*[{]/ {
      if (since != "") {
        # the record timestamp, outside "message": the first on the line when it comes before
        # "message" (Claude Code 2.1.296 writes it there), else the last; a tool input inside the
        # message may carry others
        p = index($0, "\"message\":"); ts = ""
        if (match($0, /"timestamp":[ \t]*"[^"]*"/) && p > 0 && RSTART < p) ts = substr($0, RSTART, RLENGTH)
        else { r = $0; while (match(r, /"timestamp":[ \t]*"[^"]*"/)) { ts = substr(r, RSTART, RLENGTH); r = substr(r, RSTART + RLENGTH) } }
        if (ts == "") next
        sub(/^"timestamp":[ \t]*"/, "", ts)
        if (substr(ts, 1, 19) < since) next
      }
      if (!match($0, /"id":[ \t]*"msg_[^"]*"/)) next
      id = substr($0, RSTART, RLENGTH); sub(/^"id":[ \t]*/, "", id)
      m = "unknown"
      if (match($0, /"model":[ \t]*"[^"]*"/)) { m = substr($0, RSTART, RLENGTH); sub(/^"model":[ \t]*"/, "", m); sub(/"$/, "", m) }
      if (m == "<synthetic>") next   # placeholder messages of the CLI, all zeros
      # the message usage is the last on the line (a tool input in its content may hold another)
      r = $0; u = ""
      while (match(r, /"usage":[ \t]*[{]/)) { u = substr(r, RSTART); r = substr(r, RSTART + RLENGTH) }
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
    # older than 7 x 24 hours to the minute (-mtime +7 would keep a file up to 8 days old)
    [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -name '*.json' -mmin +10080 -print -delete
    exit 0 ;;
  --since)
    [ $# -eq 2 ] || { echo "usage: --since <UTC time, e.g. 2026-10-05T17:00:00Z, or Unix seconds>" >&2; exit 2; }
    since="$2"; bad="--since needs YYYY-MM-DDTHH:MM:SS in UTC (Z or nothing after it) or Unix seconds, got $2"
    case "$since" in
      '' | *[!0-9]*)
        re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z?$'   # no other offset
        [[ $since =~ $re ]] || { echo "$bad" >&2; exit 2; } ;;
      *)
        # Unix seconds (the status line's resets_at): GNU date reads @<n>, BSD date -r <n>
        [ ${#since} -le 10 ] || { echo "$bad" >&2; exit 2; }
        if date --version >/dev/null 2>&1; then since="$(date -u -d "@$since" +%Y-%m-%dT%H:%M:%S)"
        else since="$(date -u -r "$since" +%Y-%m-%dT%H:%M:%S)"; fi ;;
    esac
    [ -d "$cfg/projects" ] || { echo "no transcripts in $cfg/projects" >&2; exit 1; }
    find "$cfg/projects" -name '*.jsonl' -type f -exec cat {} + | SINCE="$since" count
    exit 0 ;;
esac
[ $# -eq 1 ] || exit 2
main=""
if [ -f "$arg" ]; then main="$arg"; elif [ -d "$cfg/projects" ]; then
  # the full id, else a unique prefix (claude --bg and claude agents print 8 characters)
  main="$(find "$cfg/projects" -maxdepth 2 -name "$arg.jsonl" 2>/dev/null | head -n 1)"
  if [ -z "$main" ]; then
    found="$(find "$cfg/projects" -maxdepth 2 -name "$arg*.jsonl" 2>/dev/null || true)"
    if [ "$(printf '%s' "$found" | grep -c .)" -gt 1 ]; then
      # ids only: the folder names would show other projects
      echo "ambiguous id $arg:" >&2; printf '%s\n' "$found" | sed 's|.*/||; s|\.jsonl$||' | LC_ALL=C sort >&2; exit 1
    fi
    main="$found"
  fi
  if [ -z "$main" ]; then
    # a subagent's agentId (the Agent tool's result): its transcript sits in its parent's subagents/ folder
    found="$(find "$cfg/projects" -mindepth 4 -maxdepth 4 -path '*/subagents/*' -name "agent-$arg*.jsonl" 2>/dev/null || true)"
    if [ "$(printf '%s' "$found" | grep -c .)" -gt 1 ]; then
      echo "ambiguous id $arg:" >&2; printf '%s\n' "$found" | sed 's|.*/agent-||; s|\.jsonl$||' | LC_ALL=C sort >&2; exit 1
    fi
    main="$found"
  fi
fi
sid="$arg"
if [ -n "$main" ]; then sid="$(basename "$main" .jsonl)"
elif [ ! -f "$dir/$arg.json" ] && [ -d "$dir" ]; then
  # no transcript: a status file by a unique prefix
  found="$(find "$dir" -maxdepth 1 -type f -name "$arg*.json" 2>/dev/null || true)"
  if [ "$(printf '%s' "$found" | grep -c .)" -gt 1 ]; then
    echo "ambiguous id $arg:" >&2; printf '%s\n' "$found" | sed 's|.*/||; s|\.json$||' | LC_ALL=C sort >&2; exit 1
  fi
  [ -z "$found" ] || sid="$(basename "$found" .json)"
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

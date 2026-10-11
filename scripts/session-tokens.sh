#!/usr/bin/env bash
# Tokens a Claude Code session used (macOS / Linux, no dependencies; Windows: session-tokens.ps1).
#   scripts/session-tokens.sh <session-id | transcript.jsonl>
# Prints lines for RUNS.tsv (CORE §7), from two sources when both exist:
#   status      <in+out>  in=<n> out=<n> cost=$<usd>   — the CLI's own totals, from the status line's
#               per-session file ~/.claude/coordinator/sessions/<id>.json (TOOLKIT *Usage*); preferred
#   transcript  <total>   in=<n> out>=<n> cache_read=<n> cache_write=<n>   — summed from the session's
#               transcript and its subagents; input and cache counts are exact, output is a LOWER
#               BOUND (the transcript stores the output count from before a message finished)
# Exit 1 when neither exists. Reads the JSON as text (one record per line), no parser needed.
set -eu
[ $# -eq 1 ] || { sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 2; }
arg="$1"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # Claude Code's own override of ~/.claude
if [ -f "$arg" ]; then main="$arg"; else
  main="$(find "$cfg/projects" -maxdepth 2 -name "$arg.jsonl" 2>/dev/null | head -n 1)"
fi
sid="$(basename "${main:-$arg}" .jsonl)"
status="$cfg/coordinator/sessions/$sid.json"
if [ -f "$status" ]; then
  awk '
    function num(k,   t) { if (!match(s, "\"" k "\"[ \t]*:[ \t]*-?[0-9.eE+-]+")) return "?"
                           t = substr(s, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", t); return t }
    { s = s $0 }
    END { i = num("total_input_tokens"); o = num("total_output_tokens"); c = num("total_cost_usd")
          printf "status\t%.0f\tin=%s out=%s cost=$%s\n", (i == "?" ? 0 : i) + (o == "?" ? 0 : o), i, o, c }' "$status"
fi
if [ -n "${main:-}" ] && [ -f "$main" ]; then
  sub="${main%.jsonl}/subagents"
  { cat "$main"; [ -d "$sub" ] && find "$sub" -maxdepth 1 -name '*.jsonl' -exec cat {} + ; true; } | awk '
    # an assistant record: top-level "type":"assistant", its message id (msg_…) and the usage object
    function num(k,   t) { if (!match(u, "\"" k "\":[ \t]*[0-9]+")) return 0
                           t = substr(u, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", t); return t + 0 }
    /"type":[ \t]*"assistant"/ && /"usage":[ \t]*[{]/ {
      if (!match($0, /"id":[ \t]*"msg_[^"]*"/)) next
      id = substr($0, RSTART, RLENGTH); sub(/^"id":[ \t]*/, "", id)
      match($0, /"usage":[ \t]*[{]/); u = substr($0, RSTART)
      o = num("output_tokens")
      if (!(id in out) || o > out[id]) { out[id] = o; inp[id] = num("input_tokens")
        rd[id] = num("cache_read_input_tokens"); wr[id] = num("cache_creation_input_tokens") }
    }
    END { for (id in out) { I += inp[id]; O += out[id]; R += rd[id]; W += wr[id] }
          printf "transcript\t%.0f\tin=%.0f out>=%.0f cache_read=%.0f cache_write=%.0f\n", I + O + R + W, I, O, R, W }'
elif [ ! -f "$status" ]; then
  echo "no transcript or status file for $arg" >&2; exit 1
fi

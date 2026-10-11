#!/usr/bin/env bash
# Tokens a Claude Code session used, read from its transcript (macOS / Linux, needs jq).
#   scripts/session-tokens.sh <session-id | transcript.jsonl>
# Prints one line for RUNS.tsv (CORE §7):  <total>  in=<n> out=<n> cache_read=<n> cache_write=<n>
# Sums every assistant message once (a message spans several transcript lines with the same usage),
# including the session's own subagents (<session>/subagents/*.jsonl).
set -euo pipefail
arg="${1:?usage: session-tokens.sh <session-id | transcript.jsonl>}"
if [ -f "$arg" ]; then main="$arg"; else
  main="$(find "$HOME/.claude/projects" -maxdepth 2 -name "$arg.jsonl" 2>/dev/null | head -n 1)"
  [ -n "$main" ] || { echo "no transcript for $arg under ~/.claude/projects" >&2; exit 1; }
fi
files=("$main")
sub="${main%.jsonl}/subagents"
[ -d "$sub" ] && for f in "$sub"/*.jsonl; do [ -f "$f" ] && files+=("$f"); done
cat "${files[@]}" | jq -rs '
  map(select(.type == "assistant" and .message.usage != null))
  | unique_by(.message.id) | map(.message.usage)
  | { i: (map(.input_tokens // 0) | add // 0), o: (map(.output_tokens // 0) | add // 0),
      r: (map(.cache_read_input_tokens // 0) | add // 0), w: (map(.cache_creation_input_tokens // 0) | add // 0) }
  | "\(.i + .o + .r + .w)\tin=\(.i) out=\(.o) cache_read=\(.r) cache_write=\(.w)"'

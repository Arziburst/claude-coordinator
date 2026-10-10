#!/usr/bin/env bash
# Status line for coordinator machines: saves Claude Code's status JSON (incl. rate_limits on Pro / Max)
# to ~/.claude/coordinator/statusline.json so the coordinator can read its usage, and prints a short line.
input="$(cat)"
dir="$HOME/.claude/coordinator"
mkdir -p "$dir" 2>/dev/null && printf '%s' "$input" > "$dir/statusline.json"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -r '[.model.display_name // "claude",
    (if .rate_limits.five_hour then "5h \(.rate_limits.five_hour.used_percentage|floor)%" else empty end),
    (if .rate_limits.seven_day then "week \(.rate_limits.seven_day.used_percentage|floor)%" else empty end)] | join(" · ")'
else
  echo "coordinator"
fi

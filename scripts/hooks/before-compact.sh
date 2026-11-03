#!/usr/bin/env bash
# A PreCompact hook for a coordinator (#342): before Claude Code compacts the conversation it writes
# <cwd>/coordinator/CHECKPOINT.md - the moment, the journal's open questions, the watch list, this project's
# sessions (claude agents --json, 10 s at most: past that only the process this hook started is killed) and
# the files to re-read - which after-compact.sh coordinator puts back into the context: a summary is
# precomputed hours before the swap and never holds it. Never blocks a compaction: exit 0 on any failure,
# one line on stderr; silent without <cwd>/coordinator, in a worktree, with a kept brief (a worker) or
# COORD_ASSISTANT_DIR (an assistant). At most 8000 bytes: a section over its share keeps its first lines
# and says truncated. Windows: before-compact.ps1, the same file.
#   bash scripts/hooks/before-compact.sh          (reads the hook's JSON on stdin; the project is its cwd)
in="$(cat 2>/dev/null)"
str() { printf '%s' "$in" | tr -d '\r\n' | sed -n "s/.*\"$1\" *: *\"\\([^\"]*\\)\".*/\\1/p"; }
sid="$(str session_id)"; wd="$(str cwd | sed 's/\\\\/\\/g' | tr '\\' '/')"; cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ -n "$wd" ] && [ -z "${COORD_ASSISTANT_DIR:-}" ] || exit 0
case "$wd" in */.claude/worktrees/*|*/.claude/worktrees) exit 0 ;; esac
case "$sid" in *[!0-9a-fA-F-]*|"") ;; *) [ ! -f "$cfg/coordinator/briefs/$sid.md" ] || exit 0 ;; esac
c="$wd/coordinator"; [ -d "$c" ] || exit 0
fail() { echo "before-compact: $1" >&2; }
# the lines under LOG.md's "## Open questions" up to its next heading
if [ -f "$c/LOG.md" ] && q="$(LC_ALL=C awk '/^## / { on = /^## Open questions/; next } on' "$c/LOG.md" 2>/dev/null)"; then :
else q="could not read coordinator/LOG.md"; fail "cannot read $c/LOG.md"; fi
w="$(cat "$c/watch.txt" 2>/dev/null)"
# the sessions whose cwd is the project or inside it: `<id> <state> <name>`; the listing to a file, never a
# pipe (a process left under a killed claude would hold it); killed past 10 s by the handle this hook got
r="$(printf 'coordinator/%s\n' core/CORE.md PROJECT.md BINDINGS.md LOG.md)"; s=""; t="$(mktemp -d 2>/dev/null)" || t=""
[ -z "$t" ] || { claude agents --json > "$t/out" 2>/dev/null < /dev/null & p=$!; n=0
  while kill -0 "$p" 2>/dev/null; do [ "$n" -lt 100 ] || { kill -9 "$p" 2>/dev/null; break; }; sleep 0.1; n=$((n + 1)); done; }
if [ -n "$t" ] && wait "$p" 2>/dev/null && [ "$n" -lt 100 ]; then
  s="$(WD="$wd" LC_ALL=C awk 'BEGIN { RS = "\001"; wd = tolower(ENVIRON["WD"]) }
    function g(o, k,   v) { if (!match(o, "\"" k "\" *: *\"[^\"]*\"")) return ""; v = substr(o, RSTART, RLENGTH); sub(/^[^:]*: *"/, "", v); sub(/"$/, "", v); return v }
    { j = j $0 } END { while (match(j, /\{[^{}]*\}/)) { o = substr(j, RSTART, RLENGTH); j = substr(j, RSTART + RLENGTH); d = tolower(g(o, "cwd")); gsub(/\\+/, "/", d)
      if (d == wd || index(d, wd "/") == 1) print g(o, "id") " " g(o, "state") " " g(o, "name") } }' "$t/out")"
else s="could not list the sessions"; fail "no session listing (claude agents --json failed or did not answer in 10 s)"; fi
[ -z "$t" ] || rm -rf "$t"
# sec <heading> <share in bytes> <text>: the text's first lines within the share, then `truncated`
sec() { printf '## %s\n' "$1"; printf '%s\n' "$3" | LC_ALL=C awk -v m="$2" '{ sub(/\r$/, ""); n += length($0) + 1; if (n > m) { print "truncated"; exit } print }'; }
out="$(printf 'written: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; sec "Open questions" 3200 "$q"; sec "Watch list" 1600 "$w"; sec "Sessions" 2400 "$s"; sec "Re-read" 400 "$r")"
printf '%s\n' "$out" 2>/dev/null > "$c/CHECKPOINT.md" || fail "cannot write $c/CHECKPOINT.md"
exit 0

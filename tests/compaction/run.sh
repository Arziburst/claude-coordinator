#!/usr/bin/env bash
# The checkpoint before and after a compaction (#342):  tests/compaction/run.sh sh | ps <powershell|pwsh>
# Access points, as the worker implements them:
# - scripts/hooks/before-compact.{sh,ps1}, no arguments, the hook's JSON on stdin; the project is its `cwd`. Always exit 0;
#   a failure: one stderr line. Silent, nothing written: no <cwd>/coordinator, a worktree cwd, a kept brief or COORD_ASSISTANT_DIR.
# - <cwd>/coordinator/CHECKPOINT.md, UTF-8, at most 8000 bytes, no other CHECKPOINT* left beside it, in this order:
#   `written: YYYY-MM-DDTHH:MM:SSZ`; `## Open questions`: the lines under LOG.md's `## Open questions` up to its next heading, or
#   `could not read coordinator/LOG.md`; `## Watch list`: coordinator/watch.txt's lines; `## Sessions`: from `claude agents --json`,
#   one line each with id, state and name, only a cwd that is the project or inside it, or one `could not list the sessions` line
#   (the listing's bound 10 s); `## Re-read`: coordinator/core/CORE.md, coordinator/PROJECT.md, coordinator/BINDINGS.md,
#   coordinator/LOG.md, a line each. A section over its share keeps its first lines and says `truncated`; the later ones stay.
# - The settings: no entry in any settings.example*; ONE-TIME.md and TOOLKIT.md each name `PreCompact` and `before-compact` (a project's
#   .claude/settings.json, as the coordinator's after-compact), its timeout over the listing's bound.
# - after-compact coordinator: today's text, then the file's content in additionalContext (raw UTF-8, valid JSON), the whole stdout
#   at most 10000 bytes (over that: `truncated`). Says `checkpoint is missing` (absent or unreadable) or `checkpoint is stale`
#   (`written:` over 60 minutes old, or none): a note, never a loss, the content printed either way. Its worker and assistant variants never read the file.
set -u
kind="${1:-}"; [ $# -gt 0 ] && shift; PS=("$@")
case "$kind" in sh) ;; ps) [ ${#PS[@]} -gt 0 ] || { echo "ps needs the PowerShell command" >&2; exit 2; } ;; *) sed -n '2p' "$0" >&2; exit 2 ;; esac
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
jp() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1" | sed 's/\\/\\\\/g'; else printf '%s' "$1"; fi; }   # as JSON holds a path
unset COORD_ASSISTANT_DIR; export CLAUDE_CONFIG_DIR; CLAUDE_CONFIG_DIR="$(wp "$tmp/cfg")"; mkdir -p "$tmp/cfg/coordinator/briefs" "$tmp/away"
bin="$tmp/bin"; mkdir -p "$bin"; export STUB="$tmp/stub"; mkdir -p "$STUB"
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" agents "*) ;; *) exit 9 ;; esac
[ -f "$STUB/fail" ] && { echo "stub: no listing" >&2; exit 1; }
[ -f "$STUB/hang" ] && ( cd / && sleep 40 </dev/null >/dev/null 2>&1 )
cat "$STUB/list"
EOF
printf '%s\n' "& bash (Join-Path \$PSScriptRoot 'claude') @args" 'exit $LASTEXITCODE' > "$bin/claude.ps1"; chmod +x "$bin/claude"
export PATH="$bin:$PATH"; [ "$(command -v claude)" = "$bin/claude" ] || { echo "FAIL: the stub claude is not first on PATH"; exit 1; }
fail=0; n=0; cn=""; cb=0
c() { [ -n "$cn" ] && [ "$cb" = 0 ] && echo "ok   $cn"; cn="$1"; cb=0; [ -n "$1" ] && n=$((n + 1)); }
bad() { echo "FAIL $cn: $*"; cb=1; fail=1; }
has() { grep -qF -- "$2" "$1" 2>/dev/null || bad "no '$2' in ${1##*/}"; }
no() { ! grep -qF -- "$2" "$1" 2>/dev/null || bad "'$2' in ${1##*/}"; }
max() { [ "$(wc -c < "$1")" -le "$2" ] 2>/dev/null || bad "${1##*/} over $2 bytes: $(wc -c < "$1" 2>/dev/null)"; }
hook() {   # hook <before|after> <stdin> [role]: stdout to $tmp/out, stderr to $tmp/err, the exit code to rc; run from elsewhere
  local s="$core/scripts/hooks/$1-compact"
  if [ "$kind" = ps ]; then ( cd "$tmp/away" && printf '%s' "$2" | "${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$(wp "$s.ps1")" ${3:+"$3"} > "$tmp/out.raw" 2> "$tmp/err.raw" )
  else ( cd "$tmp/away" && printf '%s' "$2" | bash "$s.sh" ${3:+"$3"} > "$tmp/out.raw" 2> "$tmp/err.raw" ); fi
  rc=$?; tr -d '\r' < "$tmp/out.raw" > "$tmp/out"; tr -d '\r' < "$tmp/err.raw" > "$tmp/err"
}
js() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"%s","trigger":"auto"}' "${2:-c0c00000-0000-4000-8000-000000000001}" "$(jp "$1")" "${3:-PreCompact}"; }
before() { hook before "$(js "$1" "${2:-}")"; [ "$rc" = 0 ] || bad "before: exit $rc"; }
# the hook's stdout as one valid JSON line, its additionalContext decoded into $tmp/ctx
after() { hook after "$(js "$1" "" SessionStart)" "${2:-coordinator}"; [ "$rc" = 0 ] || bad "after: exit $rc"; : > "$tmp/ctx"
  LC_ALL=C awk -v P='{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"' '
    NR > 1 { print "more than one line"; exit 1 } index($0, P) != 1 || substr($0, length($0) - 2) != "\"}}" { print "not the JSON shape"; exit 1 }
    { s = substr($0, length(P) + 1, length($0) - length(P) - 3); o = ""
      while (match(s, /[\\"\001-\037]/)) { c = substr(s, RSTART + 1, 1); if (substr(s, RSTART, 1) != "\\" || index("\"\\/bfnrt", c) == 0) { print "a bad character in the string"; exit 1 }
        o = o substr(s, 1, RSTART - 1) (c == "n" ? "\n" : c == "t" ? "\t" : c == "r" ? "" : c); s = substr(s, RSTART + 2) }
      printf "%s%s\n", o, s > CTX }' CTX="$tmp/ctx" "$tmp/out" > "$tmp/json" || bad "stdout: $(cat "$tmp/json")"; }
stamp() { local s=$(( $(date +%s) - $1 )); if date --version >/dev/null 2>&1; then date -u -d "@$s" "$2"; else date -u -r "$s" "$2"; fi; }
TODAY='Act on the files, not on the summary.'; Q3="OPEN-Q3 $(printf '\320\262\320\276\320\277\321\200\320\276\321\201')"; Q2="OPEN-Q2 \"quoted\" back\\slash$(printf '\t')tabbed"
list() { printf '[\n'; printf '  {"id":"aaaa1111","cwd":"%s","name":"SESSION-HERE","state":"working"},\n  {"id":"bbbb2222","cwd":"%s","name":"SESSION-WT","state":"idle"},\n  {"id":"cccc3333","cwd":"%s","name":"SESSION-ELSEWHERE","state":"working"}\n]\n' "$(jp "$1")" "$(jp "$1/.claude/worktrees/7-x")" "$(jp "$1-other")"; }
mk() { rm -r "$1" 2>/dev/null; mkdir -p "$1/coordinator"; rm -f "$STUB/fail" "$STUB/hang"; list "$1" > "$STUB/list"
  printf '# Journal\n## Open questions\n- 2026-11-01: OPEN-Q1 which database?\n- 2026-11-02: %s\n- 2026-11-02: %s\n## Events\n- 2026-11-01: EVENT-LINE started\n' "$Q2" "$Q3" > "$1/coordinator/LOG.md"
  printf 'aaaa1111\nWATCHED-WORKER @120\n' > "$1/coordinator/watch.txt"; }
P="$tmp/proj"; F="$P/coordinator/CHECKPOINT.md"; S="$tmp/settings"
c "the settings: ONE-TIME and TOOLKIT name the entry, no settings example holds it"
for x in ONE-TIME.md TOOLKIT.md; do has "$core/$x" PreCompact; has "$core/$x" before-compact; done
for x in "$core"/settings.example*.json; do grep -v '^  "_comment"' "$x" > "$S"; no "$S" PreCompact; no "$S" before-compact; done
c "before: the file holds the moment, the open questions, the watch list, this project's sessions, what to re-read"
mk "$P"; before "$P"; grep -Eq '^written: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$F" || bad "no written line"
for t in '## Open questions' OPEN-Q1 '## Watch list' 'WATCHED-WORKER @120' '## Sessions' '## Re-read' coordinator/core/CORE.md coordinator/PROJECT.md coordinator/BINDINGS.md coordinator/LOG.md; do has "$F" "$t"; done
grep -q 'aaaa1111.*working.*SESSION-HERE\|SESSION-HERE.*working.*aaaa1111' "$F" || bad "no line with the session's id, state and name"; has "$F" SESSION-WT
no "$F" SESSION-ELSEWHERE; no "$F" EVENT-LINE; [ "$(ls "$P/coordinator" | grep -c '^CHECKPOINT')" = 1 ] || bad "a temp file left: $(ls "$P/coordinator")"
c "before then after: the session is told all of it, beside today's text, and neither word"
after "$P"; for t in "$TODAY" OPEN-Q1 WATCHED-WORKER SESSION-HERE SESSION-WT coordinator/BINDINGS.md "$(sed -n 1p "$F")"; do has "$tmp/ctx" "$t"; done
no "$tmp/ctx" 'checkpoint is missing'; no "$tmp/ctx" 'checkpoint is stale'
c "a quote, a backslash, a tab and Cyrillic in a question come through byte for byte"
has "$F" "$Q3"; has "$tmp/ctx" "$Q2"; has "$tmp/ctx" "$Q3"
c "no coordinator folder, or stdin that is no JSON: nothing written"
mkdir -p "$tmp/bare"; before "$tmp/bare"; [ -z "$(ls -A "$tmp/bare")" ] || bad "wrote: $(ls -A "$tmp/bare")"
hook before 'not json'; [ "$rc" = 0 ] || bad "not json: exit $rc"; [ -z "$(ls -A "$tmp/away")" ] || bad "wrote in the hook's folder"
c "a worker's or an assistant's session writes nothing: a worktree, a kept brief, COORD_ASSISTANT_DIR"
W="$P/.claude/worktrees/7-x"; mk "$P"; mkdir -p "$W/coordinator"; before "$W"; [ ! -e "$W/coordinator/CHECKPOINT.md" ] || bad "wrote in a worktree"
b=5e550000-0000-4000-8000-000000000001; : > "$tmp/cfg/coordinator/briefs/$b.md"; before "$P" "$b"; [ ! -e "$F" ] || bad "wrote with a kept brief"; rm "$tmp/cfg/coordinator/briefs/$b.md"
export COORD_ASSISTANT_DIR="$(wp "$tmp/away")"; before "$P"; unset COORD_ASSISTANT_DIR; [ ! -e "$F" ] || bad "wrote in an assistant's session"
c "a missing journal: said, the rest kept"
mk "$P"; rm "$P/coordinator/LOG.md"; before "$P"; has "$F" 'could not read coordinator/LOG.md'; has "$F" WATCHED-WORKER; has "$F" SESSION-HERE
c "a journal that cannot be read: said, one line on stderr, the rest kept"
mk "$P"; rm "$P/coordinator/LOG.md"; mkdir "$P/coordinator/LOG.md"; before "$P"; has "$F" 'could not read coordinator/LOG.md'; has "$F" WATCHED-WORKER
[ "$(grep -c . "$tmp/err")" = 1 ] || bad "stderr: $(cat "$tmp/err")"
if [ "$kind" = ps ] && command -v cygpath >/dev/null 2>&1; then c "a journal held open by another process (Windows): said, the rest kept"
  mk "$P"; "${PS[@]}" -NoProfile -Command "\$f=[IO.File]::Open('$(wp "$P/coordinator/LOG.md")','Open','ReadWrite','None'); [IO.File]::WriteAllText('$(wp "$tmp/held")','x'); Start-Sleep 8; \$f.Close()" & h=$!
  until [ -f "$tmp/held" ]; do sleep 1; done; before "$P"; wait $h; has "$F" 'could not read coordinator/LOG.md'; has "$F" WATCHED-WORKER; fi
c "a checkpoint that cannot be written: exit 0, one line on stderr; after says missing"
mk "$P"; mkdir "$F"; before "$P"; [ "$(grep -c . "$tmp/err")" = 1 ] || bad "stderr: $(cat "$tmp/err")"; after "$P"; has "$tmp/ctx" 'checkpoint is missing'; has "$tmp/ctx" "$TODAY"
c "claude fails: said, the rest kept"
mk "$P"; : > "$STUB/fail"; before "$P"; has "$F" 'could not list the sessions'; has "$F" OPEN-Q1; no "$F" SESSION-HERE
c "claude hangs: the hook ends within its entry's timeout, said, the rest kept"
mk "$P"; : > "$STUB/hang"; t0=$SECONDS; before "$P"; [ $((SECONDS - t0)) -le 25 ] || bad "took $((SECONDS - t0)) s"; has "$F" 'could not list the sessions'; has "$F" coordinator/core/CORE.md; rm -f "$STUB/hang"
c "a very long journal: bounded, its first questions and every later section kept"
mk "$P"; { printf '## Open questions\n- OPEN-Q1 first\n'; awk 'BEGIN { for (i = 0; i < 20000; i++) printf "- 2026-11-02: OPEN-LONG %d a question of about sixty characters in all\n", i }'; } > "$P/coordinator/LOG.md"
before "$P"; max "$F" 8000; has "$F" truncated; for t in OPEN-Q1 WATCHED-WORKER SESSION-HERE coordinator/LOG.md; do has "$F" "$t"; done; after "$P"; max "$tmp/out" 10000; has "$tmp/ctx" coordinator/BINDINGS.md
c "a very long watch list and listing: bounded, the re-read lines kept"
mk "$P"; awk 'BEGIN { for (i = 0; i < 3000; i++) printf "w%07d\n", i }' > "$P/coordinator/watch.txt"
{ printf '['; awk -v d="$(jp "$P")" 'BEGIN { for (i = 0; i < 3000; i++) printf "%s\n  {\"id\":\"s%07d\",\"cwd\":\"%s\",\"name\":\"LONG\",\"state\":\"idle\"}", (i ? "," : ""), i, d }'; printf '\n]\n'; } > "$STUB/list"
before "$P"; max "$F" 8000; has "$F" truncated; has "$F" OPEN-Q1; has "$F" coordinator/BINDINGS.md
c "after on a grown file: its stdout bounded, valid, today's text kept"
mk "$P"; { printf 'written: %s\n' "$(stamp 0 +%Y-%m-%dT%H:%M:%SZ)"; awk 'BEGIN { for (i = 0; i < 20000; i++) printf "line %d of a checkpoint grown by hand, far over its bound\n", i }'; } > "$F"
after "$P"; max "$tmp/out" 10000; has "$tmp/ctx" truncated; has "$tmp/ctx" "$TODAY"
c "after with no checkpoint (a project without the entry): today's text, and it says missing"
mk "$P"; after "$P"; has "$tmp/ctx" "$TODAY"; has "$tmp/ctx" 'checkpoint is missing'
c "after on a checkpoint two hours old: says stale, still prints it"
mk "$P"; printf 'written: %s\nSTALE-CONTENT\n' "$(stamp 7200 +%Y-%m-%dT%H:%M:%SZ)" > "$F"; touch -t "$(stamp 7200 +%Y%m%d%H%M.%S)" "$F" 2>/dev/null
after "$P"; has "$tmp/ctx" 'checkpoint is stale'; has "$tmp/ctx" STALE-CONTENT; no "$tmp/ctx" 'checkpoint is missing'
c "after on a checkpoint with no written line: a note, the content still printed"
printf 'NO-MOMENT-CONTENT\n' > "$F"; after "$P"; has "$tmp/ctx" 'checkpoint is stale'; has "$tmp/ctx" NO-MOMENT-CONTENT
c "after on a checkpoint thirty minutes old: not stale"
printf 'written: %s\nFRESH-CONTENT\n' "$(stamp 1800 +%Y-%m-%dT%H:%M:%SZ)" > "$F"; after "$P"; has "$tmp/ctx" FRESH-CONTENT; no "$tmp/ctx" 'checkpoint is stale'
c "guard (green before the change too): a worker's and an assistant's after-compact never read the file"
printf 'written: %s\nFRESH-CONTENT\n' "$(stamp 0 +%Y-%m-%dT%H:%M:%SZ)" > "$F"; for r in worker assistant; do after "$P" "$r"; no "$tmp/ctx" FRESH-CONTENT; no "$tmp/ctx" CHECKPOINT.md; no "$tmp/ctx" 'checkpoint is'; done
c ""
[ "$fail" = 0 ] && echo "compaction: $n cases passed" || echo "compaction: failures above ($n cases)"
exit "$fail"

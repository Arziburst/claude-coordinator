#!/usr/bin/env bash
# cc-formats (#559) against a stub `claude` on PATH (the real one is never called) and the synthetic fixtures here, in a
# temp CLAUDE_CONFIG_DIR, in few process starts: each field of its table removed (the table below names the run that
# removes it; a run removes several and its one FAIL line must name each, nothing more), all present (one PASS line,
# nothing written outside the scratch folder), --if-changed against the stub's `claude --version`, a listing that never
# answers (5 s), no status line (the payload part one SKIP line), and the line of selftest env.
#   tests/cc-formats/run.sh sh                  # cc-formats.sh, selftest.sh
#   tests/cc-formats/run.sh ps pwsh             # cc-formats.ps1, selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
bin="$tmp/bin"; cfg="$(w "$tmp/cfg")"; export CLAUDE_CONFIG_DIR="$cfg" STUB_DIR="$tmp/stub"; mkdir "$bin"
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in --version) echo "$(cat "$STUB_DIR/version") (Claude Code)" ;; agents) [ ! -f "$STUB_DIR/hang" ] || exec sleep 8; cat "$STUB_DIR/agents.json" ;; esac
EOF
# Windows only (elsewhere PowerShell runs the bash stub itself, one PowerShell less a run): claude.ps1, which PowerShell finds first
command -v cygpath >/dev/null 2>&1 && printf '%s\n' "& bash (Join-Path \$PSScriptRoot 'claude') @args" 'exit $LASTEXITCODE' > "$bin/claude.ps1"
chmod +x "$bin/claude"; export PATH="$bin:$PATH"
fails=0; bad() { echo "FAIL: $1 - exit $rc: $out"; fails=$((fails + 1)); }
# cc [args]: the probe of this shell, its output (no CR) in $out, its exit code in $rc
cc() {
  if [ "$kind" = sh ]; then out="$(bash "$core/scripts/cc-formats.sh" "$@" 2>&1)"; rc=$?
  else local a=() x; for x in "$@"; do case "$x" in --if-changed) x=-IfChanged ;; --payload) x=-Payload ;; esac; a+=("$x"); done
    out="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/cc-formats.ps1" ${a[@]+"${a[@]}"} 2>&1)"; rc=$?; fi
  out="${out//$'\r'/}"
}
setup() { rm -rf "$tmp/cfg" "$STUB_DIR"; mkdir -p "$tmp/cfg/projects/p" "$tmp/cfg/coordinator" "$STUB_DIR"
  cp "$here/transcript.jsonl" "$tmp/cfg/projects/p/s.jsonl"; cp "$here/statusline.json" "$tmp/cfg/coordinator/"
  cp "$here/agents.json" "$here/hook.json" "$STUB_DIR/"; echo 2.1.300 > "$STUB_DIR/version"; }
# edit <file key> <from> <to>: the text replaced in that input
edit() { local f; case "$1" in agents) f="$STUB_DIR/agents.json" ;; transcript) f="$tmp/cfg/projects/p/s.jsonl" ;;
  statusline) f="$tmp/cfg/coordinator/statusline.json" ;; hook) f="$STUB_DIR/hook.json" ;; esac
  awk -v a="$2" -v b="$3" '{ while ((i = index($0, a)) > 0) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' "$f" > "$f.x" && mv "$f.x" "$f"; }
snap() { (cd "$tmp/cfg" && find . -type f ! -path './coordinator/cc-formats/*' | sort | while IFS= read -r f; do cksum "$f"; done); }
# each field of the table, the run that removes it: `<run>|<input>|<from>|<to>|<format field>`
T='hang|statusline|"session_id":|"sessionId":|payload session_id
hang|statusline|"cwd":|"dir":|payload cwd
hang|statusline|"project_dir":|"projectDir":|payload workspace.project_dir
hang|statusline|"transcript_path":|"transcriptPath":|payload transcript_path
hang|statusline|"total_cost_usd":|"total_cost":|payload cost.total_cost_usd
hang|statusline|"display_name":|"displayName":|payload model.display_name
hang|statusline|"context_window_size":|"size":|payload context_window.context_window_size
agents|agents|"startedAt":|"started":|agents startedAt
agents|agents|"id":|"jobId":|agents id
agents|agents|"sessionId":|"sid":|agents sessionId
agents|agents|"cwd":|"dir":|agents cwd
agents|agents|"name":|"title":|agents name
agents|agents|"state":|"phase":|agents state
hook|hook|"command":|"cmd":|payload tool_input.command
hook|hook|"transcript_path":|"transcriptPath":|payload transcript_path
new|transcript|"type":"assistant"|"type":"model"|transcript type
new|transcript|"timestamp":|"time":|transcript timestamp
new|transcript|"cwd":|"dir":|transcript cwd
new|transcript|"message":|"msg":|transcript message
new|transcript|"id":"msg_|"id":"m_|transcript message.id
new|transcript|"model":|"modelId":|transcript model
new|transcript|"usage":|"tokens":|transcript usage
new|transcript|"input_tokens":|"in_tokens":|transcript input_tokens
new|transcript|"output_tokens":|"out_tokens":|transcript output_tokens
new|transcript|"cache_read_input_tokens":|"cache_read":|transcript cache_read_input_tokens
new|transcript|"cache_creation_input_tokens":|"cache_write":|transcript cache_creation_input_tokens
new|transcript|"stop_reason":|"stopReason":|transcript stop_reason
new|transcript|"turnOrigin":|"origin":|transcript turnOrigin
new|transcript|"type":"tool_use","id":|"type":"tool_use","use_id":|transcript tool_use.id
new|transcript|"tool_use_id":|"toolUseId":|transcript tool_use_id'
# remove <run>: its rows' fields removed from their inputs, each `<format field> (read by ` in want
remove() { want=(); while IFS='|' read -r r in from to exp; do [ "$r" = "$1" ] || continue; edit "$in" "$from" "$to"; want+=("$exp (read by "); done <<< "$T"; }
# named <run> <version> [<another item>]: one FAIL line whose items are each removed field (and that item), nothing more
named() { local body="${out#cc-formats: FAIL claude $2: }" e k=${#want[@]}; [ -z "${3:-}" ] || k=$((k + 1))
  [ "$rc" = 1 ] && [ "$body" != "$out" ] && [[ $out != *$'\n'* ]] || { bad "run $1: one FAIL line"; return; }
  [ "$(printf '%s\n' "$body" | awk -F'; ' '{ print NF }')" = "$k" ] || bad "run $1: $k items named"
  for e in "${want[@]}"; do case "; $body" in *"; $e"*) ;; *) bad "run $1: ${e% (read by } not named" ;; esac; done
  [ -z "${3:-}" ] || case "; $body;" in *"; $3;"*) ;; *) bad "run $1: '$3' not named" ;; esac; }

# hang: a listing that never answers (first: its stub's sleep ends while the other runs go), the payload's fields removed
setup; : > "$STUB_DIR/hang"; remove hang; s=$SECONDS; cc; named hang 2.1.300 "agents: claude agents --json --all did not answer in 5 s"
[ $((SECONDS - s)) -le 10 ] || bad "a listing that never answers: the line within 10 s (took $((SECONDS - s)) s)"
# no status line here: the payload part one SKIP line, the rest decides (run agents: its FAIL; all present: the PASS, recorded)
sk="cc-formats: SKIP payload: no status line here ($cfg/coordinator/statusline.json absent)"
setup; rm "$tmp/cfg/coordinator/statusline.json"; remove agents; cc; [ "${out%%$'\n'*}" = "$sk" ] || bad "no status line: the SKIP line"
out="${out#*$'\n'}"; named agents 2.1.300
setup; rm "$tmp/cfg/coordinator/statusline.json"; cc
[ "$rc" = 0 ] && [ "$out" = "$sk"$'\n'"cc-formats: PASS claude 2.1.300, 21 fields" ] || bad "no status line, the rest present: SKIP, PASS"
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version" 2>/dev/null)" = 2.1.300 ] || bad "no status line: the version recorded at the PASS"
setup; remove hook; cc --payload "$(w "$STUB_DIR/hook.json")"; named hook 2.1.300
# all present: one PASS line, the version recorded, nothing else under the config changed
setup; b="$(snap)"; cc
[ "$rc" = 0 ] && [ "$out" = "cc-formats: PASS claude 2.1.300, 28 fields" ] || bad "all fields present: one PASS line"
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version" 2>/dev/null)" = 2.1.300 ] || bad "the version recorded at a PASS"
[ "$(snap)" = "$b" ] || bad "nothing written outside the scratch folder"
# --if-changed: silent on the recorded version; a new one probed (run new: a FAIL keeps the old record), then recorded at its PASS
cc --if-changed; [ "$rc" = 0 ] && [ -z "$out" ] || bad "--if-changed on the recorded version: nothing"
echo 2.1.301 > "$STUB_DIR/version"; remove new; cc --if-changed; named new 2.1.301
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version")" = 2.1.300 ] || bad "a FAIL keeps the version unrecorded"
cp "$here/transcript.jsonl" "$tmp/cfg/projects/p/s.jsonl"; cc --if-changed
[ "$rc" = 0 ] && [ "$out" = "cc-formats: PASS claude 2.1.301, 28 fields" ] || bad "--if-changed on a new version: the PASS"
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version")" = 2.1.301 ] || bad "the new version recorded"
# selftest env on a new version: the probe's one line (gh may be absent here: its lines are not checked)
echo 2.1.302 > "$STUB_DIR/version"
if [ "$kind" = sh ]; then out="$(bash "$core/scripts/selftest.sh" env 2>&1)"
else out="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/selftest.ps1" env 2>&1)"; fi
out="${out//$'\r'/}"; rc=-
[ "$(printf '%s\n' "$out" | grep -c 'cc-formats')" = 1 ] && printf '%s\n' "$out" | grep -qx 'PASS env: cc-formats claude 2.1.302, 28 fields' ||
  bad "selftest env on a new version: the probe's one PASS line"
[ "$fails" = 0 ] && echo "cc-formats: all checks passed ($kind)" || { echo "cc-formats: $fails failed"; exit 1; }

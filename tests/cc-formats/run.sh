#!/usr/bin/env bash
# cc-formats (#559) against a stub `claude` on PATH (the real one is never called) and the synthetic fixtures here, in a
# temp CLAUDE_CONFIG_DIR: each field of its table removed, one per case (a FAIL naming it), all present (one PASS line,
# nothing written outside the scratch folder), --if-changed against the stub's `claude --version`, a listing that never
# answers (5 s), and the line of selftest env.
#   tests/cc-formats/run.sh sh                  # cc-formats.sh, selftest.sh
#   tests/cc-formats/run.sh ps pwsh             # cc-formats.ps1, selftest.ps1 (or: ps powershell)
# Exit 1 if any check fails.
set -u
[ $# -gt 0 ] || { sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift; PS=("$@")
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
w() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
bin="$tmp/bin"; cfg="$(w "$tmp/cfg")"; export CLAUDE_CONFIG_DIR="$cfg" STUB_DIR="$tmp/stub"; mkdir "$bin"
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$1" in --version) echo "$(cat "$STUB_DIR/version") (Claude Code)" ;; agents) [ ! -f "$STUB_DIR/hang" ] || exec sleep 7; cat "$STUB_DIR/agents.json" ;; esac
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

# the hang first: its stub's sleep ends while the other cases run
setup; : > "$STUB_DIR/hang"; s=$SECONDS; cc
[ "$rc" = 1 ] && [ "$out" = "cc-formats: FAIL claude 2.1.300: agents: claude agents --json --all did not answer in 5 s" ] &&
  [ $((SECONDS - s)) -le 10 ] || bad "a listing that never answers: one FAIL line within 10 s (took $((SECONDS - s)) s)"

# each field removed: `<input> <from> <to> <format field>`, the hook's on the payload given by --payload
while IFS='|' read -r in from to exp; do
  setup; edit "$in" "$from" "$to"
  if [ "$in" = hook ]; then cc --payload "$(w "$STUB_DIR/hook.json")"; else cc; fi
  [ "$rc" = 1 ] && [[ $out == "cc-formats: FAIL claude 2.1.300: $exp (read by "*")" && $out != *";"* && $out != *$'\n'* ]] ||
    bad "$exp removed: one FAIL line naming it and its readers"
done <<'EOF'
agents|"id":|"jobId":|agents id
agents|"sessionId":|"sid":|agents sessionId
agents|"cwd":|"dir":|agents cwd
agents|"name":|"title":|agents name
agents|"state":|"phase":|agents state
transcript|"type":"assistant"|"type":"model"|transcript type
transcript|"timestamp":|"time":|transcript timestamp
transcript|"cwd":|"dir":|transcript cwd
transcript|"message":|"msg":|transcript message
transcript|"id":"msg_|"id":"m_|transcript message.id
transcript|"model":|"modelId":|transcript model
transcript|"usage":|"tokens":|transcript usage
transcript|"input_tokens":|"in_tokens":|transcript input_tokens
transcript|"output_tokens":|"out_tokens":|transcript output_tokens
transcript|"cache_read_input_tokens":|"cache_read":|transcript cache_read_input_tokens
transcript|"cache_creation_input_tokens":|"cache_write":|transcript cache_creation_input_tokens
transcript|"stop_reason":|"stopReason":|transcript stop_reason
transcript|"turnOrigin":|"origin":|transcript turnOrigin
transcript|"type":"tool_use","id":|"type":"tool_use","use_id":|transcript tool_use.id
transcript|"tool_use_id":|"toolUseId":|transcript tool_use_id
statusline|"session_id":|"sessionId":|payload session_id
statusline|"cwd":|"dir":|payload cwd
statusline|"project_dir":|"projectDir":|payload workspace.project_dir
hook|"command":|"cmd":|payload tool_input.command
EOF

# all present: one PASS line, the version recorded, nothing else under the config changed; the hook's sample passes too
setup; b="$(snap)"; cc
[ "$rc" = 0 ] && [ "$out" = "cc-formats: PASS claude 2.1.300, 23 fields" ] || bad "all fields present: one PASS line"
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version" 2>/dev/null)" = 2.1.300 ] || bad "the version recorded at a PASS"
[ "$(snap)" = "$b" ] || bad "nothing written outside the scratch folder"
cc --payload "$(w "$STUB_DIR/hook.json")"; [ "$rc" = 0 ] && [ "$out" = "cc-formats: PASS claude 2.1.300, 23 fields" ] || bad "the hook's sample passes"
# --if-changed: silent on the recorded version; a new one probed (a FAIL keeps the old record), then recorded at its PASS
cc --if-changed; [ "$rc" = 0 ] && [ -z "$out" ] || bad "--if-changed on the recorded version: nothing"
echo 2.1.301 > "$STUB_DIR/version"; edit transcript '"usage":' '"tokens":'; cc --if-changed
[ "$rc" = 1 ] && [[ $out == "cc-formats: FAIL claude 2.1.301: transcript usage (read by "* ]] || bad "--if-changed on a new version: the FAIL"
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version")" = 2.1.300 ] || bad "a FAIL keeps the version unrecorded"
edit transcript '"tokens":' '"usage":'; cc --if-changed
[ "$rc" = 0 ] && [ "$out" = "cc-formats: PASS claude 2.1.301, 23 fields" ] || bad "--if-changed on a new version: the PASS"
[ "$(cat "$tmp/cfg/coordinator/cc-formats/version")" = 2.1.301 ] || bad "the new version recorded"

# selftest env: the probe's line once, then none (gh may be absent here: its lines are not checked)
setup
for i in 1 2; do
  if [ "$kind" = sh ]; then out="$(bash "$core/scripts/selftest.sh" env 2>&1)"
  else out="$("${PS[@]}" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/selftest.ps1" env 2>&1)"; fi
  out="${out//$'\r'/}"; rc=$i; got="$(printf '%s\n' "$out" | grep -c 'cc-formats')"
  if [ "$i" = 1 ]; then printf '%s\n' "$out" | grep -qx 'PASS env: cc-formats claude 2.1.300, 23 fields' && [ "$got" = 1 ] || bad "selftest env: the probe's PASS line"
  else [ "$got" = 0 ] || bad "selftest env on the recorded version: no probe line"; fi
done
[ "$fails" = 0 ] && echo "cc-formats: all checks passed ($kind)" || { echo "cc-formats: $fails failed"; exit 1; }

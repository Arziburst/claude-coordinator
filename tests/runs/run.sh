#!/usr/bin/env bash
# The runs cases (#332): `add` appends one run row to a RUNS.tsv with its numbers from session-tokens
# (every allowed result word, a header in another order, no header, a free-text result refused, a missing
# transcript refused, the same session and role twice refused, an assistant twice allowed, CRLF and a BOM
# kept, a file without a final newline, a subagent row `--in <parent>`), and `check` lists the project's
# finished sessions with no row (another folder, the coordinator's own session, an assistant, a working
# session and a logged one never listed; a worktree outside the root listed; --since; ALL LOGGED; a failed
# listing), reading only. Fixture transcripts in a temporary config folder (CLAUDE_CONFIG_DIR, never the
# real ~/.claude) and a stub `claude` first on PATH (the real claude is never called).
#   tests/runs/run.sh sh                 # scripts/runs.sh, with the bash running this file
#   tests/runs/run.sh ps pwsh            # scripts/runs.ps1 (or: ps powershell)
# Exit 1 if any case fails.
#
# Access points the script implements as written here (#332):
#   runs.sh  add --log <RUNS.tsv> --session <id> --task <n> --role <role> --kind <kind> --model <m>
#                --effort <e> --estimate <cost|-> --estimate-time <t|-> --result <word> [--date <YYYY-MM-DD>]
#   runs.sh  add --log <RUNS.tsv> --in <parent> --tokens <n> --task … --result <word> [--date …]
#                (a subagent row: no --session)
#   runs.sh  check --log <RUNS.tsv> --root <project root> [--self <sessionId>] [--since <YYYY-MM-DD>]
#   runs.ps1 add|check (the first argument) with -Log -Session -Task -Role -Kind -Model -Effort -Estimate
#            -EstimateTime -Result -Date -In -Tokens -Root -Self -Since (each --x-y as -XY)
#   add: the row's cells by the file's header (a first line whose fields include `date` and `role`), else
#     CORE §7's order: date task role kind model effort estimate tokens cost result start wall active wait
#     estimate_time. tokens = the `total` line's number of `scripts/session-tokens <id>` (the same config
#     folder, CLAUDE_CONFIG_DIR); cost = its `cost` line's number (a leading `$` optional, words after it
#     allowed); start / wall / active = its `time` line's start= / wall= / active= (minutes, no `m`); wait
#     empty; estimate_time = --estimate-time. With --in: tokens = --tokens, cost `in <parent>`, start, wall
#     and active empty. The written row is printed on stdout. The file keeps its BOM and its line ends (a
#     CRLF file gets a CRLF row, an LF file an LF row); a last line without a newline is ended first.
#     Result words: approved done pass `rework <n>` (one argument, n a number) escalated failed dropped
#     ready; any other: exit 2, the file byte-identical. No transcript for --session: exit 1, file
#     unchanged. A row already there with the same start and role: refused, exit non-zero, file unchanged
#     — except role `assistant`.
#   add / check: a log that cannot be written (add) or read (add, check; e.g. a directory in its place, a
#     file held open without sharing): exit 1 with a line starting `runs:`, no row on stdout, never
#     ALL LOGGED, the log unchanged.
#   check: the sessions from `claude agents --json --all` (its only claude call; fields id, sessionId,
#     name, cwd, state, status). Finished = the process ended: state done, stopped or failed and no
#     status field; working, or any status (idle - a worker waiting between rounds - or busy) = not
#     finished. A session belongs to the project when its cwd is the root or
#     inside it, or the root or inside of a worktree of the root's git repository (`git worktree list`),
#     compared as paths (C:\x and C:/x the same; /x/app-other is not inside /x/app). Never listed: --self
#     (its sessionId or short id), a name starting `assistant:`. Its start = the session-tokens `time`
#     line's start=; a session is logged when a row's start cell equals it. --since: only sessions whose
#     start date is that date or later. Output: `MISSING <id> <name> <start>` per session, exit 0; none:
#     `ALL LOGGED`, exit 0; claude failing: exit 1, never ALL LOGGED. It writes nothing.
set -u
[ $# -gt 0 ] || { sed -n '2,12s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"   # PATH takes this form; the paths handed to the scripts take the Windows form below
command -v cygpath >/dev/null 2>&1 && { core="$(cygpath -m "$core")"; tmp="$(cygpath -m "$tmp")"; }
unset CLAUDE_CODE_SESSION_ID
export CLAUDE_CONFIG_DIR="$tmp/cfg"   # session-tokens reads the fixture transcripts here, never ~/.claude

# The stub claude: logs every call's arguments to $STUB_D/log; answers with $STUB_D/agents.json, or fails
# (exit 1) when $STUB_D/fail exists.
mkdir -p "$bin"
cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_D/log"
[ -f "$STUB_D/fail" ] && { echo "stub: listing failed" >&2; exit 1; }
[ "$*" = "agents --json --all" ] || { echo "stub: unexpected call: $*" >&2; exit 3; }
cat "$STUB_D/agents.json"
EOF
# PowerShell finds claude.ps1 first on Windows; it hands the arguments to the bash stub
cat > "$bin/claude.ps1" <<'EOF'
& bash (Join-Path $PSScriptRoot 'claude') @args
exit $LASTEXITCODE
EOF
chmod +x "$bin/claude"
export PATH="$bin:$PATH"
[ "$(command -v claude)" = "$bin/claude" ] || { echo "FAIL: the stub claude is not first on PATH ($(command -v claude))"; exit 1; }
export STUB_D="$tmp/stub"; mkdir -p "$STUB_D"

case "$kind" in
  sh) runs() { bash "$core/scripts/runs.sh" "$@"; } ;;
  ps) ps="${1:-pwsh}"
      runs() { local a=("$1"); shift
        while [ $# -gt 0 ]; do
          case "$1" in
            --estimate-time) a+=("-EstimateTime:$2"); shift 2 ;;
            --*) local o="${1#--}"; a+=("-$(printf '%s' "${o:0:1}" | tr a-z A-Z)${o:1}:$2"); shift 2 ;;
            *) a+=("$1"); shift ;;
          esac
        done
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/runs.ps1" "${a[@]}"; } ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

# ---- fixtures ----
# tx <folder> <sessionId> <cwd> <t1> <t2> <t3> <cost>: a transcript of three assistant messages at those
# times (10:00, +3 m, +20 m: wall 20, active 3) and the status line's file with its cost
tx() { local d="$CLAUDE_CONFIG_DIR/projects/$1" s="$2" c="$3"; mkdir -p "$d" "$CLAUDE_CONFIG_DIR/coordinator/sessions"
  local i=0 t
  for t in "$4" "$5" "$6"; do i=$((i + 1))
    printf '{"parentUuid":null,"isSidechain":false,"cwd":"%s","sessionId":"%s","version":"2.1.296","type":"assistant","message":{"id":"msg_%s_%d","type":"message","role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":%d,"cache_creation_input_tokens":1000,"cache_read_input_tokens":20000,"output_tokens":300}},"uuid":"u%d","timestamp":"%s"}\n' \
      "$c" "$s" "${s:0:8}" $i $((i * 7)) $i "$t" >> "$d/$s.jsonl"
  done
  printf '{"session_id":"%s","cost":{"total_cost_usd":%s}}\n' "$s" "$7" > "$CLAUDE_CONFIG_DIR/coordinator/sessions/$s.json"
}
ROOT="$tmp/proj"; WT="$tmp/elsewhere/wt"; OTHER="$tmp/proj-other"
mkdir -p "$ROOT/sub/dir" "$OTHER" "$tmp/elsewhere"
git -C "$ROOT" init -q && git -C "$ROOT" -c user.name=t -c user.email=t@t.invalid commit -q --allow-empty -m init &&
  git -C "$ROOT" worktree add -q "$WT" -b wt-332 || { echo "FAIL: cannot set up the git fixture"; exit 1; }
# the sessions: <var> <short id> <sessionId>
W1=a1b2c3d4 W1S=a1b2c3d4-0000-4000-8000-000000000001   # worker in a subfolder of the root, done
W2=b2c3d4e5 W2S=b2c3d4e5-0000-4000-8000-000000000002   # tester in a worktree outside the root, stopped
W3=c3d4e5f6 W3S=c3d4e5f6-0000-4000-8000-000000000003   # verifier in the root, failed, logged
FO=d4e5f6a7 FOS=d4e5f6a7-0000-4000-8000-000000000004   # another folder (its path starts as the root's), done
CO=e5f6a7b8 COS=e5f6a7b8-0000-4000-8000-000000000005   # the coordinator's own session, done
AS=f6a7b8c9 ASS=f6a7b8c9-0000-4000-8000-000000000006   # an assistant in the root, done
WK=a7b8c9d0 WKS=a7b8c9d0-0000-4000-8000-000000000007   # a working session in the root
BZ=b8c9d0e1 BZS=b8c9d0e1-0000-4000-8000-000000000008   # done but status busy, in the root
OL=c9d0e1f2 OLS=c9d0e1f2-0000-4000-8000-000000000009   # an older finished session in the root, before --since
tx -proj-sub-dir "$W1S" "$ROOT/sub/dir" 2026-10-01T10:00:00.000Z 2026-10-01T10:03:00.000Z 2026-10-01T10:20:00.000Z 1.2345
tx -elsewhere-wt "$W2S" "$WT" 2026-10-02T10:00:00.000Z 2026-10-02T10:03:00.000Z 2026-10-02T10:20:00.000Z 0.5
tx -proj "$W3S" "$ROOT" 2026-10-03T10:00:00.000Z 2026-10-03T10:03:00.000Z 2026-10-03T10:20:00.000Z 0.25
tx -proj-other "$FOS" "$OTHER" 2026-10-04T10:00:00.000Z 2026-10-04T10:03:00.000Z 2026-10-04T10:20:00.000Z 0.75
tx -proj "$COS" "$ROOT" 2026-10-05T10:00:00.000Z 2026-10-05T10:03:00.000Z 2026-10-05T10:20:00.000Z 2.0
tx -proj "$ASS" "$ROOT" 2026-10-06T10:00:00.000Z 2026-10-06T10:03:00.000Z 2026-10-06T10:20:00.000Z 0.125
tx -proj "$WKS" "$ROOT" 2026-10-07T10:00:00.000Z 2026-10-07T10:03:00.000Z 2026-10-07T10:20:00.000Z 0.1
tx -proj "$BZS" "$ROOT" 2026-10-08T10:00:00.000Z 2026-10-08T10:03:00.000Z 2026-10-08T10:20:00.000Z 0.1
tx -proj "$OLS" "$ROOT" 2026-09-01T10:00:00.000Z 2026-09-01T10:03:00.000Z 2026-09-01T10:20:00.000Z 0.3
# jpath <dir>: the cwd as claude prints it, JSON-escaped (on Windows the C:\... form)
jpath() { local p="$1"; command -v cygpath >/dev/null 2>&1 && p="$(cygpath -w "$p")"; printf '%s' "$p" | sed 's/\\/\\\\/g'; }
# agent <id> <sessionId> <name> <cwd> <state> [<status>]
agent() { printf '  {\n    "id": "%s",\n    "sessionId": "%s",\n    "name": "%s",\n    "cwd": "%s",\n    "state": "%s"%s\n  }' \
  "$1" "$2" "$3" "$(jpath "$4")" "$5" "${6:+,
    \"status\": \"$6\"}"; }
{ echo "["
  agent $W1 $W1S "#12 worker: Fix the log" "$ROOT/sub/dir" done; echo ","
  agent $W2 $W2S "#12 tester" "$WT" stopped; echo ","
  agent $W3 $W3S "#11 verifier" "$ROOT" failed; echo ","
  agent $FO $FOS "#12 worker: other project" "$OTHER" done; echo ","
  agent $CO $COS "coordinator" "$ROOT" done; echo ","
  agent $AS $ASS "assistant: hours" "$ROOT" done; echo ","
  agent $WK $WKS "#13 worker" "$ROOT" working busy; echo ","
  agent $BZ $BZS "#14 worker" "$ROOT" done busy; echo ","
  agent $OL $OLS "#9 worker" "$ROOT" done
  echo; echo "]"; } > "$STUB_D/agents.json"

# st <sessionId> <what>: what session-tokens prints for the fixture: tokens, cost, start, wall, active
# (read once per session into $tmp/st/)
mkdir -p "$tmp/st"
for s in $W1S $W2S $W3S $OLS $ASS; do bash "$core/scripts/session-tokens.sh" "$s" | tr -d '\r' > "$tmp/st/$s" &&
  grep -q '^time' "$tmp/st/$s" || { echo "FAIL: session-tokens does not read the fixture $s"; exit 1; }; done
st() { awk -v w="$2" '
  $1 == "total" && w == "tokens" { print $2 }
  $1 == "cost" && w == "cost" { v = $2; sub(/^\$/, "", v); print v }
  $1 == "time" { for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == w) { v = kv[2]; sub(/m$/, "", v); print v } } }' "$tmp/st/$1"; }

# ---- the checks ----
pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$name] $*"; printf '%s\n' "$out" | sed 's/^/    | /'; }
H="$(printf 'date\ttask\trole\tkind\tmodel\teffort\testimate\ttokens\tcost\tresult\tstart\twall\tactive\twait\testimate_time')"
OLD="$(printf '2026-10-01\t11\tverifier\tverifier\thaiku\tlow\t-\t900\tin 11\tpass\t2026-10-03T10:00:00Z\t9\t7\t\t-')"
n=0
# fresh <name>: a new run log path $L (not created); the stub's call log emptied
fresh() { name="$1"; n=$((n + 1)); L="$tmp/log$n.tsv"; : > "$STUB_D/log"; rm -f "$STUB_D/fail"; }
run() { runs "$@" > "$tmp/out.raw" 2>&1; rc=$?; out="$(tr -d '\r' < "$tmp/out.raw")"; }
code() { [ "$rc" = "$1" ] && ok || bad "expected exit $1, got $rc"; }
fails() { [ "$rc" != 0 ] && ok || bad "expected a refusal (exit non-zero), got 0"; }
has() { printf '%s\n' "$out" | grep -qE -- "$1" && ok || bad "expected a line matching: $1"; }
hasnt() { printf '%s\n' "$out" | grep -qE -- "$1" && bad "unexpected: $1" || ok; }
same() { cmp -s "$1" "$2" && ok || bad "the file changed"; }
# rows <file>: the number of data rows (no header, no comment, no empty line)
rows() { tr -d '\r' < "$1" | sed '1s/^\xEF\xBB\xBF//' | awk -F'\t' '
  NR == 1 { h = 0; for (i = 1; i <= NF; i++) if ($i == "date" || $i == "role") h++; if (h == 2) next }
  /^#/ || /^$/ { next } { n++ } END { print n + 0 }'; }
# crs <file>: the number of CR bytes in it (grep on Windows may hide them)
crs() { tr -cd '\r' < "$1" | wc -c | tr -d ' '; }
# cell <file> <column> [<row from the end, 1 the last>]: by the file's header, else CORE §7's order
cell() { tr -d '\r' < "$1" | sed '1s/^\xEF\xBB\xBF//' | awk -F'\t' -v c="$2" -v k="${3:-1}" -v H="$H" '
  NR == 1 { h = 0; for (i = 1; i <= NF; i++) if ($i == "date") h++; else if ($i == "role") h++
            if (h == 2) { for (i = 1; i <= NF; i++) col[$i] = i; next }
            m = split(H, d, "\t"); for (i = 1; i <= m; i++) col[d[i]] = i }
  /^#/ || /^$/ { next } { r[++nr] = $0 }
  END { split(r[nr - k + 1], f, "\t"); print f[col[c]] }'; }
lastline() { tr -d '\r' < "$1" | awk 'NF { l = $0 } END { print l }'; }
# row_ok <file> <sessionId> <task> <role> <result>: the last row's cells against the options and session-tokens
row_ok() { local f="$1" s="$2" v want
  for v in date:2026-10-31 task:$3 role:$4 kind:ordinary model:opus effort:medium estimate:3 estimate_time:30-60 wait:; do
    want="${v#*:}"; [ "$(cell "$f" "${v%%:*}")" = "$want" ] && ok || bad "column ${v%%:*}: '$(cell "$f" "${v%%:*}")', want '$want'"
  done
  [ "$(cell "$f" result)" = "$5" ] && ok || bad "column result: '$(cell "$f" result)', want '$5'"
  for v in tokens start wall active; do
    want="$(st "$s" $v)"; [ -n "$want" ] && [ "$(cell "$f" $v)" = "$want" ] && ok || bad "column $v: '$(cell "$f" $v)', want session-tokens' '$want'"
  done
  want="$(st "$s" cost)"; v="$(cell "$f" cost | sed 's/^\$//; s/ .*//')"
  [ -n "$want" ] && awk -v a="$v" -v b="$want" 'BEGIN { exit !(a != "" && a + 0 == b + 0) }' && ok || bad "column cost: '$(cell "$f" cost)', want session-tokens' '$want'"
  printf '%s\n' "$out" | grep -qxF -- "$(lastline "$f")" && ok || bad "the written row is not printed"
}
A=(--task 12 --role worker --kind ordinary --model opus --effort medium --estimate 3 --estimate-time 30-60 --date 2026-10-31)

# add: every allowed result word
for w in approved done pass "rework 2" escalated failed dropped ready; do
  fresh "add --result $w: one row in the header's order, numbers from session-tokens"
  printf '%s\n%s\n' "$H" "$OLD" > "$L"; cp "$L" "$L.before"
  run add --log "$L" --session $W1S "${A[@]}" --result "$w"
  code 0; [ "$(rows "$L")" = 2 ] && ok || bad "rows: $(rows "$L"), want 2"
  [ "$(head -c "$(wc -c < "$L.before")" "$L" | cmp -s - "$L.before"; echo $?)" = 0 ] && ok || bad "the earlier lines changed"
  [ "$(crs "$L")" = 0 ] && ok || bad "an LF file got a CR"
  row_ok "$L" $W1S 12 worker "$w"
done

fresh "add: a header in another order - the cells by that header"
printf 'task\tdate\tresult\trole\tkind\tmodel\teffort\testimate\testimate_time\ttokens\tcost\tstart\twall\tactive\twait\n' > "$L"
run add --log "$L" --session $W1S "${A[@]}" --result approved
code 0; [ "$(rows "$L")" = 1 ] && ok || bad "rows: $(rows "$L"), want 1"; row_ok "$L" $W1S 12 worker approved

fresh "add: a file without a header - CORE §7's order"
printf '%s\n' "$OLD" > "$L"
run add --log "$L" --session $W1S "${A[@]}" --result done
code 0; [ "$(rows "$L")" = 2 ] && ok || bad "rows: $(rows "$L"), want 2"; row_ok "$L" $W1S 12 worker done
[ "$(lastline "$L" | awk -F'\t' '{ print NF }')" = 15 ] && ok || bad "the row has $(lastline "$L" | awk -F'\t' '{ print NF }') fields, want 15"

for w in ok "looks fine" rework "rework two" "approved!"; do
  fresh "add --result '$w': refused, exit 2, the file byte-identical"
  printf '%s\n%s\n' "$H" "$OLD" > "$L"; cp "$L" "$L.before"
  run add --log "$L" --session $W1S "${A[@]}" --result "$w"
  code 2; same "$L" "$L.before"
done

fresh "add: no transcript for the session - exit 1, the file unchanged"
printf '%s\n%s\n' "$H" "$OLD" > "$L"; cp "$L" "$L.before"
run add --log "$L" --session 0badf00d-0000-4000-8000-00000000dead "${A[@]}" --result approved
code 1; same "$L" "$L.before"

fresh "add: the same session and role twice - the second refused, the file unchanged"
printf '%s\n' "$H" > "$L"
run add --log "$L" --session $W1S "${A[@]}" --result approved; code 0; cp "$L" "$L.before"
run add --log "$L" --session $W1S "${A[@]}" --result approved; fails; same "$L" "$L.before"

fresh "add: role assistant twice in one session - both written, the same start"
printf '%s\n' "$H" > "$L"
B=(--task hours --role assistant --kind assistant --model sonnet --effort low --estimate - --estimate-time - --result done)
run add --log "$L" --session $ASS "${B[@]}" --date 2026-10-30; code 0
run add --log "$L" --session $ASS "${B[@]}" --date 2026-10-31; code 0
[ "$(rows "$L")" = 2 ] && ok || bad "rows: $(rows "$L"), want 2"
[ "$(cell "$L" start 1)" = "$(st $ASS start)" ] && [ "$(cell "$L" start 2)" = "$(st $ASS start)" ] && ok || bad "the assistant rows' start differs from session-tokens'"

fresh "add: a CRLF file with a BOM keeps both; the row ends CRLF"
printf '\xEF\xBB\xBF%s\r\n%s\r\n' "$H" "$OLD" > "$L"; cp "$L" "$L.before"
run add --log "$L" --session $W1S "${A[@]}" --result approved
code 0; [ "$(rows "$L")" = 2 ] && ok || bad "rows: $(rows "$L"), want 2"
[ "$(head -c "$(wc -c < "$L.before")" "$L" | cmp -s - "$L.before"; echo $?)" = 0 ] && ok || bad "the BOM or the earlier lines changed"
[ "$(grep -c $'\xEF\xBB\xBF' "$L")" = 1 ] && ok || bad "BOMs: $(grep -c $'\xEF\xBB\xBF' "$L"), want 1"
[ "$(tail -c 2 "$L" | od -An -c | tr -d ' ')" = '\r\n' ] && ok || bad "the last line does not end CRLF"
[ "$(tr -cd '\n' < "$L" | wc -c | tr -d ' ')" = "$(crs "$L")" ] && ok || bad "a line without its CR"
row_ok "$L" $W1S 12 worker approved

fresh "add: a last line without a newline - the row on a line of its own"
printf '%s\n%s' "$H" "$OLD" > "$L"
run add --log "$L" --session $W1S "${A[@]}" --result approved
code 0; [ "$(rows "$L")" = 2 ] && ok || bad "rows: $(rows "$L"), want 2"
tr -d '\r' < "$L" | grep -qxF -- "$OLD" && ok || bad "the earlier last row was changed"
row_ok "$L" $W1S 12 worker approved

fresh "add --in <parent> --tokens <n>: a subagent row, cost 'in <parent>', time columns empty"
printf '%s\n' "$H" > "$L"
run add --log "$L" --in 12 --tokens 4567 --task 12 --role verifier --kind verifier --model haiku --effort low --estimate - --estimate-time - --result pass --date 2026-10-31
code 0; [ "$(rows "$L")" = 1 ] && ok || bad "rows: $(rows "$L"), want 1"
for v in tokens:4567 "cost:in 12" role:verifier result:pass start: wall: active:; do
  [ "$(cell "$L" "${v%%:*}")" = "${v#*:}" ] && ok || bad "column ${v%%:*}: '$(cell "$L" "${v%%:*}")', want '${v#*:}'"
done
printf '%s\n' "$out" | grep -qxF -- "$(lastline "$L")" && ok || bad "the written row is not printed"

# check
LOGGED="$(printf '2026-10-03\t11\tverifier\tverifier\thaiku\tlow\t-\t900\t0.25\tfailed\t%s\t20\t3\t\t-' "$(st $W3S start)")"
calls_ok() { [ -s "$STUB_D/log" ] && ! grep -vxq -- 'agents --json --all' "$STUB_D/log" && ok || bad "claude calls: $(tr '\n' ';' < "$STUB_D/log"), want only 'agents --json --all'"; }

fresh "check: MISSING for this project's finished sessions with no row, nothing else; reads only"
printf '%s\n%s\n' "$H" "$LOGGED" > "$L"; cp "$L" "$L.before"
run check --log "$L" --root "$ROOT" --self $COS
code 0; same "$L" "$L.before"; calls_ok
has "^MISSING $W1 #12 worker: Fix the log $(st $W1S start)\$"
has "^MISSING $W2 #12 tester $(st $W2S start)\$"
has "^MISSING $OL #9 worker $(st $OLS start)\$"
for x in $W3 $FO $CO $AS $WK $BZ; do hasnt "$x"; done
hasnt "ALL LOGGED"
[ "$(printf '%s\n' "$out" | grep -c '^MISSING ')" = 3 ] && ok || bad "MISSING lines: $(printf '%s\n' "$out" | grep -c '^MISSING '), want 3"

fresh "check --since: a session started before that date is not listed"
printf '%s\n%s\n' "$H" "$LOGGED" > "$L"; cp "$L" "$L.before"
run check --log "$L" --root "$ROOT" --self $COS --since 2026-10-01
code 0; same "$L" "$L.before"; calls_ok
has "^MISSING $W1 "; has "^MISSING $W2 "; hasnt "$OL"

fresh "check: every finished session logged - ALL LOGGED"
{ printf '\xEF\xBB\xBF%s\r\n%s\r\n' "$H" "$LOGGED"
  for s in $W1S $W2S $OLS; do printf '2026-10-01\t12\tworker\tordinary\topus\tmedium\t3\t1\t0.1\tapproved\t%s\t20\t3\t\t-\r\n' "$(st $s start)"; done; } > "$L"
cp "$L" "$L.before"
run check --log "$L" --root "$ROOT" --self $COS
code 0; same "$L" "$L.before"; calls_ok; has "^ALL LOGGED\$"; hasnt "^MISSING"

fresh "check: the coordinator's own session by its short id with --self"
printf '%s\n%s\n' "$H" "$LOGGED" > "$L"
run check --log "$L" --root "$ROOT" --self $CO
code 0; hasnt "$CO"; has "^MISSING $W1 "

fresh "check: claude agents fails - exit 1, never ALL LOGGED, nothing written"
printf '%s\n%s\n' "$H" "$LOGGED" > "$L"; cp "$L" "$L.before"; : > "$STUB_D/fail"
run check --log "$L" --root "$ROOT" --self $COS
code 1; hasnt "ALL LOGGED"; same "$L" "$L.before"; rm -f "$STUB_D/fail"

# a log that cannot be written or read: exit 1, a line `runs:`, no row claimed on stdout, the log unchanged
# runio <args>: as run, with stdout alone in $sout
runio() { runs "$@" > "$tmp/out.raw" 2> "$tmp/err.raw"; rc=$?; sout="$(tr -d '\r' < "$tmp/out.raw")"
  out="$(cat "$tmp/out.raw" "$tmp/err.raw" | tr -d '\r')"; }
norow() { printf '%s\n' "$sout" | grep -q "$(printf '\t')" && bad "stdout claims a row: $sout" || ok; }
refused_io() { code 1; has "^runs: "; norow; hasnt "ALL LOGGED"; }

fresh "add: a read-only log - exit 1, runs:, no row, the file byte-identical"
printf '%s\n%s\n' "$H" "$OLD" > "$L"; cp "$L" "$L.before"; chmod a-w "$L"
if [ -w "$L" ]; then echo "SKIP [$name] the file stays writable here (root?)"
else runio add --log "$L" --session $W1S "${A[@]}" --result approved; refused_io; fi
chmod u+w "$L"; same "$L" "$L.before"

fresh "add: a directory in place of the log - exit 1, runs:, no row, nothing written"
mkdir "$L"
runio add --log "$L" --session $W1S "${A[@]}" --result approved
refused_io; [ -d "$L" ] && [ -z "$(ls -A "$L")" ] && ok || bad "the directory changed"

fresh "check: a directory in place of the log - exit 1, runs:, never ALL LOGGED or a silent 0"
mkdir "$L"
runio check --log "$L" --root "$ROOT" --self $COS
refused_io; [ "$rc" = 0 ] && [ -z "$out" ] && bad "a silent exit 0" || ok; hasnt "^MISSING"

if command -v cygpath >/dev/null 2>&1; then
  # a log held open without sharing (Windows): a powershell this harness starts holds it until $L.go is gone
  fresh "add: a log held open without sharing - exit 1, runs:, the file byte-identical"
  printf '%s\n%s\n' "$H" "$OLD" > "$L"; cp "$L" "$L.before"; : > "$L.go"
  powershell -NoProfile -Command "\$f = [IO.File]::Open('$L', 'Open', 'ReadWrite', 'None'); New-Item -ItemType File '$L.ready' | Out-Null; while (Test-Path '$L.go') { Start-Sleep -Milliseconds 100 }; \$f.Close()" &
  lockpid=$!; i=0; while [ ! -f "$L.ready" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
  if [ -f "$L.ready" ]; then
    runio add --log "$L" --session $W1S "${A[@]}" --result approved; refused_io
    name="check: a log held open without sharing - exit 1, runs:, never ALL LOGGED"
    runio check --log "$L" --root "$ROOT" --self $COS; refused_io; hasnt "^MISSING"
  else echo "SKIP [$name] the log could not be held open"; fi
  rm -f "$L.go"; wait "$lockpid"; rm -f "$L.ready"; same "$L" "$L.before"
fi

# finished = the process ended: no status field and state done, stopped or failed (the coordinator's
# decision, round 2); a status idle (a worker waiting between rounds) or busy is never finished.
# Each case's listing holds one session in the root.
DN=d0e1f2a3 DNS=d0e1f2a3-0000-4000-8000-00000000000a   # done, no status
SN=e1f2a3b4 SNS=e1f2a3b4-0000-4000-8000-00000000000b   # stopped, no status
DI=f2a3b4c5 DIS=f2a3b4c5-0000-4000-8000-00000000000c   # done + idle
SI=a3b4c5d6 SIS=a3b4c5d6-0000-4000-8000-00000000000d   # stopped + idle
tx -proj "$DNS" "$ROOT" 2026-10-10T10:00:00.000Z 2026-10-10T10:03:00.000Z 2026-10-10T10:20:00.000Z 0.1
tx -proj "$SNS" "$ROOT" 2026-10-11T10:00:00.000Z 2026-10-11T10:03:00.000Z 2026-10-11T10:20:00.000Z 0.1
tx -proj "$DIS" "$ROOT" 2026-10-12T10:00:00.000Z 2026-10-12T10:03:00.000Z 2026-10-12T10:20:00.000Z 0.1
tx -proj "$SIS" "$ROOT" 2026-10-13T10:00:00.000Z 2026-10-13T10:03:00.000Z 2026-10-13T10:20:00.000Z 0.1
for s in $DNS $SNS; do bash "$core/scripts/session-tokens.sh" "$s" | tr -d '\r' > "$tmp/st/$s"; done
cp "$STUB_D/agents.json" "$tmp/agents.main.json"
# one <id> <sessionId> <name> <state> [<status>]: the listing holds this one session, in the root
one() { { echo "["; agent "$1" "$2" "$3" "$ROOT" "$4" ${5:+"$5"}; echo; echo "]"; } > "$STUB_D/agents.json"; }

fresh "check: done with no status - finished, listed"
printf '%s\n' "$H" > "$L"; one $DN $DNS "#20 worker" done
run check --log "$L" --root "$ROOT" --self $COS
code 0; has "^MISSING $DN #20 worker $(st $DNS start)\$"; hasnt "ALL LOGGED"

fresh "check: stopped with no status - finished, listed"
printf '%s\n' "$H" > "$L"; one $SN $SNS "#21 tester" stopped
run check --log "$L" --root "$ROOT" --self $COS
code 0; has "^MISSING $SN #21 tester $(st $SNS start)\$"; hasnt "ALL LOGGED"

fresh "check: done + idle (a worker waiting between rounds) - not finished, not listed"
printf '%s\n' "$H" > "$L"; one $DI $DIS "#22 worker" done idle
run check --log "$L" --root "$ROOT" --self $COS
code 0; hasnt "$DI"; has "^ALL LOGGED\$"

fresh "check: stopped + idle - not finished, not listed"
printf '%s\n' "$H" > "$L"; one $SI $SIS "#23 worker" stopped idle
run check --log "$L" --root "$ROOT" --self $COS
code 0; hasnt "$SI"; has "^ALL LOGGED\$"
cp "$tmp/agents.main.json" "$STUB_D/agents.json"

echo "runs ($kind${1:+ $1}): $pass passed, $fail failed"
[ "$fail" = 0 ]

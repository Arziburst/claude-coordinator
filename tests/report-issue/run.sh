#!/usr/bin/env bash
# Checks of report-issue (#338) against a stub `gh` on PATH (GitHub is never called): the stub answers from
# the files of a state folder and logs every call. The signature builder (the same error from two machines,
# one signature; .sh and .ps1 the same line) and filing: FIXED UPSTREAM, REPEAT (a reaction, no comment;
# the reaction already there; --comment-file), CHECK, FILED, --dry-run; every gh call but issue create,
# issue comment and the reaction POST is read-only.
#   tests/report-issue/run.sh sh                   # report-issue.sh, with the bash running this file
#   tests/report-issue/run.sh ps pwsh              # report-issue.ps1 (or: ps powershell)
# Exit 1 if any check fails.
#
# The access points the script implements as written here:
#   report-issue.sh signature --source <s> [--step <s>] [--exit <code>] --error <text>
#   report-issue.sh file --repo <owner/name> --title <t> --body-file <f> --signature <sig> [--keywords <words>]
#                        [--checked <n,n,...>] [--comment-file <f>] [--regression] [--dry-run]
#   report-issue.ps1: the mode first, then -Source -Step -Exit -ErrorText (not -Error: $Error is PowerShell's
#     own) -Repo -Title -BodyFile -Signature -Keywords -Checked <n,n,...> -CommentFile -Regression -DryRun
#   an open issue holding the signature wins over a closed one (REPEAT, never FIXED UPSTREAM); --regression
#     with only a closed-as-completed match #N files a new issue (FILED, the title as given) whose body holds
#     a line `Regression of #N` and still ends with `Signature: <sig>`, nothing written on #N; its dry run
#     prints the would-be filing naming #N; --regression with no exact match: the usual CHECK / FILED flow
#   lines: the signature alone on one line; FIXED UPSTREAM #<n> (exit 3); REPEAT #<n> (exit 0); CHECK #<a> #<b>
#     ... and each candidate's title (exit 4); FILED #<n> (exit 0)
#   gh calls (the stub answers these):
#     gh issue list --repo <r> --state all --search <query> --json number,state,stateReason,title [--limit <n>]
#       [--jq <expr>] - the exact search is the call whose arguments hold the whole signature, any other is
#       the keyword search. Without --jq the stub prints gh's JSON array (number, state, stateReason, title,
#       body); with --jq it prints `<number>\t<state>\t<stateReason>\t<title>` lines, whatever the expression
#       (so the script's expression must print that shape from gh). --limit is honoured.
#     gh api user [--jq .login]                         this account's login (JSON {"login":..} without --jq)
#     gh api repos/<r>/issues/<n>/reactions [--jq <expr>]   GET: the issue's reactions - JSON
#       [{"content":..,"user":{"login":..}}] without --jq, `<content>\t<login>` lines with it
#     gh api --method POST repos/<r>/issues/<n>/reactions -f content=+1    the reaction (-X POST, or any
#       field flag without a method, counts as the POST too)
#     gh issue create --repo <r> --title <t> --body-file <f> (or --body <text>)   prints the issue's URL
#     gh issue comment <n> --repo <r> --body-file <f> (or --body <text>)
set -u
[ $# -gt 0 ] || { sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2; }
kind="$1"; shift
here="$(cd "$(dirname "$0")" && pwd)"; core="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # Git Bash -> C:/...
core="$(winpath "$core")"

# The stub's state folder $STUB_D:
#   sig       the signature the exact search looks for      exact     the exact search's issues
#   keyword   the keyword search's issues; each issue a line `<n>\t<OPEN|CLOSED>\t<COMPLETED|NOT_PLANNED|>\t<title>`
#   login     this account's login (stub-user)               reactions-<n>  `<content>\t<login>` lines
#   next      the number issue create gives (901)            log       every call, one a line
#   created   the body of the issue created                  commented the body of the comment
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
D="$STUB_D"
# from gh.ps1: the arguments NUL-separated in a file, as PowerShell had them
if [ "${1:-}" = --stub-args ]; then f="$2"; set --; while IFS= read -r -d '' x; do set -- "$@" "$x"; done < "$f"; rm -f "$f"; fi
a="$*"; printf '%s\n' "$a" | tr '\n\t\r' '   ' >> "$D/log"; echo >> "$D/log"
opt() { local p="" x; for x in "$@"; do [ "$p" = "$O" ] && { printf '%s' "$x"; return; }; p="$x"; done; }
has() { local x; for x in "${@:2}"; do [ "$x" = "$1" ] && return 0; done; return 1; }
issues() {   # <file> <limit>: the issues, TSV with --jq, else JSON (an exact match's body ends with its Signature line)
  local lim="${2:-1000}"
  if [ -n "$J" ]; then [ -f "$1" ] && head -n "$lim" "$1"; return 0; fi
  { [ -f "$1" ] && head -n "$lim" "$1"; } | S="$(cat "$D/sig")" X="$([ "$1" = "$D/exact" ] && echo 1)" awk -F '\t' '
    function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    { b = ENVIRON["X"] ? "the report\\n\\nSignature: " q(ENVIRON["S"]) : "the body of #" $1
      printf "%s{\"number\":%s,\"state\":\"%s\",\"stateReason\":\"%s\",\"title\":\"%s\",\"body\":\"%s\"}", (NR > 1 ? "," : "["), $1, $2, $3, q($4), b }
    END { if (NR == 0) printf "["; print "]" }'; }
O=--jq; J="$(opt "$@")"
body() { O=--body-file; local f; f="$(opt "$@")"; if [ -n "$f" ]; then cat "$f"; else O=--body; opt "$@"; fi; }
case "$1 ${2:-}" in
  "issue list")
    O=--limit; l="$(opt "$@")"
    if [ -s "$D/sig" ] && case "$a" in *"$(cat "$D/sig")"*) true ;; *) false ;; esac
    then issues "$D/exact" "$l"; else issues "$D/keyword" "$l"; fi ;;
  "issue create") body "$@" > "$D/created"; n="$(cat "$D/next" 2>/dev/null || echo 901)"
    O=--repo; echo "https://github.com/$(opt "$@")/issues/$n" ;;
  "issue comment") body "$@" > "$D/commented"; echo "https://github.com/o/r/issues/$3#issuecomment-1" ;;
  "api user") l="$(cat "$D/login" 2>/dev/null || echo stub-user)"
    if [ -n "$J" ]; then echo "$l"; else printf '{"login":"%s"}\n' "$l"; fi ;;
  api\ *)
    n="$(printf '%s' "$a" | sed -n 's|.*issues/\([0-9][0-9]*\)/reactions.*|\1|p')"
    if [ -z "$n" ]; then echo "stub gh: no answer for: $a" >&2; exit 1; fi
    O=--method; m="$(opt "$@")"; [ -n "$m" ] || { O=-X; m="$(opt "$@")"; }
    if [ -z "$m" ]; then for x in "$@"; do case "$x" in -f|-F|--field|--raw-field|--input) m=POST ;; esac; done; fi
    case "$m" in ""|GET|get)
      if [ -n "$J" ]; then cat "$D/reactions-$n" 2>/dev/null; else
        printf '['; s=""; [ -f "$D/reactions-$n" ] && while IFS="$(printf '\t')" read -r c u; do
          printf '%s{"content":"%s","user":{"login":"%s"}}' "$s" "$c" "$u"; s=,; done < "$D/reactions-$n"; printf ']\n'; fi ;;
      *) echo '{"content":"+1"}' ;; esac ;;
  *) echo "stub gh: no answer for: $a" >&2; exit 1 ;;
esac
exit 0
EOF
# PowerShell finds gh.ps1 first; it hands its arguments to the bash stub through a file, so the log holds
# exactly what PowerShell passed (no second round of native quoting)
cat > "$tmp/bin/gh.ps1" <<'EOF'
$f = [IO.Path]::GetTempFileName()
$t = ''; foreach ($x in $args) { $t += [string]$x + [char]0 }
[IO.File]::WriteAllText($f, $t, (New-Object Text.UTF8Encoding $false))
& bash (Join-Path $PSScriptRoot 'gh') --stub-args ($f -replace '\\', '/')
exit $LASTEXITCODE
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"

case "$kind" in
  sh) ri() { bash "$core/scripts/report-issue.sh" "$@"; } ;;
  ps) ps="${1:-pwsh}"
      ri() { local a=() x
        for x in "$@"; do case "$x" in
          --source) a+=(-Source) ;; --step) a+=(-Step) ;; --exit) a+=(-Exit) ;; --error) a+=(-ErrorText) ;;
          --repo) a+=(-Repo) ;; --title) a+=(-Title) ;; --body-file) a+=(-BodyFile) ;; --signature) a+=(-Signature) ;;
          --keywords) a+=(-Keywords) ;; --checked) a+=(-Checked) ;; --comment-file) a+=(-CommentFile) ;;
          --regression) a+=(-Regression) ;; --dry-run) a+=(-DryRun) ;; *) a+=("$x") ;; esac; done
        "$ps" -NoProfile -ExecutionPolicy Bypass -File "$core/scripts/report-issue.ps1" "${a[@]}"; } ;;
  *) echo "unknown kind: $kind" >&2; exit 2 ;;
esac

pass=0 fail=0
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$name] $*"; printf '%s\n' "$out" | sed 's/^/    | /'; }
# fresh <name>: a new state folder; run <args>: report-issue's output and exit code
fresh() { name="$1"; export STUB_D="$tmp/s$((pass + fail))-$RANDOM"; mkdir -p "$STUB_D"; : > "$STUB_D/log"; printf '%s' "$SIG" > "$STUB_D/sig"; }
run() { out="$(ri "$@" 2>&1)"; rc=$?; out="$(printf '%s\n' "$out" | tr -d '\r')"; }
has() { printf '%s\n' "$out" | grep -qF -- "$1" && ok || bad "expected the words: $1"; }
hasnt() { printf '%s\n' "$out" | grep -qF -- "$1" && bad "unexpected: $1" || ok; }
code() { [ "$rc" = "$1" ] && ok || bad "expected exit $1, got $rc"; }
# the log's calls by kind: a write is issue create, issue comment, an api call with a method other than GET
# or a field flag without one; any other gh command than issue list/view/status, search, auth status, api
calls() {   # calls <create|comment|reaction|other-write>: how many
  awk -v k="$1" '
    { w = ""; if ($1 == "issue") { if ($2 == "create") w = "create"; else if ($2 == "comment") w = "comment"
                                     else if ($2 != "list" && $2 != "view" && $2 != "status") w = "other-write" }
      else if ($1 == "api") { m = ""; f = 0
        for (i = 2; i <= NF; i++) { if (($i == "--method" || $i == "-X") && i < NF) m = toupper($(i + 1))
          if ($i == "-f" || $i == "-F" || $i == "--field" || $i == "--raw-field" || $i == "--input") f = 1 }
        if (m == "" && f) m = "POST"
        if (m != "" && m != "GET") w = ($0 ~ /issues\/[0-9]+\/reactions/ && m == "POST") ? "reaction" : "other-write" }
      else if (!($1 == "search" || ($1 == "auth" && $2 == "status"))) w = "other-write"
      if (w == k) c++ }
    END { print c + 0 }' "$STUB_D/log"; }
count() { local got; got="$(calls "$1")"; [ "$got" = "$2" ] && ok || { bad "expected $2 $1 call(s), got $got"; sed 's/^/    log: /' "$STUB_D/log"; }; }
readonly_else() { count other-write 0; }
R=Arziburst/claude-coordinator
SIG='scripts/merge-queue.sh: land: exit 3: the update was refused by the base'
T=$'\t'
printf 'The merge queue stopped.\n\nSteps: land 12 on a behind PR.\n' > "$tmp/body.md"; BODY="$(winpath "$tmp/body.md")"
printf 'Also on macOS 15, core 3e15b27.\n' > "$tmp/comment.md"; COMMENT="$(winpath "$tmp/comment.md")"
file() { run file --repo "$R" --title "merge-queue stops when the update is refused" --body-file "$BODY" --signature "$SIG" "$@"; }

# --- signature: the same error from two machines -> one signature ---
EA=$'Error: Cannot open \'C:\\Users\\a\\x\\RUNS.tsv\'  at 2026-10-29T12:34:56Z\tfor commit 3e15b27a9c0d1e2f3a4b5c6d7e8f901234567890 (ref 3e15b27), see https://github.com/acme/one/pull/12 - 42 rows\r\n'
EB=$'error: cannot open "/home/b/x/RUNS.tsv" at 2025-01-02T03:04:05Z for commit 9f8e7d6c5b4a39281706f5e4d3c2b1a098765432 (ref abcdef1), see https://gitlab.example.org/b/two/-/merge_requests/7 - 7 rows\n'
SA=scripts/run-stats.sh
fresh "signature: paths, drive letters, ids, dates, URLs, numbers, quotes, case, whitespace and CRLF normalized"
run signature --source "$SA" --step "read the run log" --exit 1 --error "$EA"; code 0; s1="$out"
run signature --source "$SA" --step "read the run log" --exit 1 --error "$EB"; code 0; s2="$out"
[ -n "$s1" ] && [ "$s1" = "$s2" ] && ok || bad "two machines, two signatures: [$s1] [$s2]"
[ "$(printf '%s\n' "$s1" | wc -l | tr -d ' ')" = 1 ] && ok || bad "the signature is not one line"
[ "${#s1}" -le 120 ] && ok || bad "longer than 120 characters: ${#s1}"
out="$s1"
case "$s1" in "$SA: read the run log: exit 1: "*) ok ;; *) bad "does not start with <source>: <step>: exit <code>: " ;; esac
has "cannot open"; has "for commit"
for x in Error Cannot users home acme gitlab 3e15b27 abcdef1 2026 2025 12:34 '42' "'" '"' "$T" '  '; do hasnt "$x"; done
fresh "signature: at most 120 characters for a long error"
long="fatal: $(printf 'the guard refused the command again and again %.0s' 1 2 3 4 5 6)"
run signature --source scripts/hooks/safety-guard.sh --step guard --exit 2 --error "$long"; code 0
[ -n "$out" ] && [ "${#out}" -le 120 ] && ok || bad "a long error: ${#out} characters"
has "scripts/hooks/safety-guard.sh: guard: exit 2: fatal"
if [ "$kind" = ps ]; then
  fresh "signature: .ps1 prints the line .sh prints"
  sh_sig="$(bash "$core/scripts/report-issue.sh" signature --source "$SA" --step "read the run log" --exit 1 --error "$EA" 2>&1 | tr -d '\r')"
  [ -n "$s1" ] && [ "$s1" = "$sh_sig" ] && ok || bad ".ps1 [$s1] .sh [$sh_sig]"
fi

# --- signature, round 3 of #338: quoted paths with spaces, scp remotes, negative exit codes ---
# (the signature goes to a public issue: a path's tail and the names in it never reach it). Unquoted paths
# with spaces cannot be told from words: round 4 drops the rest of the line after any unquoted path start,
# UNC and user@host:/path included (below).
# sig <args>: run signature; under ps also .sh with the same arguments - the two lines byte for byte
sig() {
  run signature "$@"
  if [ "$kind" = ps ]; then
    local o="$out" r="$rc" s
    s="$(bash "$core/scripts/report-issue.sh" signature "$@" 2>&1 | tr -d '\r')"
    [ "$o" = "$s" ] && ok || bad ".ps1 [$o] .sh [$s]"
    out="$o"; rc="$r"
  fi; }
# same <error A> <error B> <word>...: both errors give one signature, holding none of the words
same() {
  local a="$1" b="$2" s
  shift 2
  sig --source scripts/run-stats.sh --step "read the run log" --exit 1 --error "$a"; code 0; s="$out"
  sig --source scripts/run-stats.sh --step "read the run log" --exit 1 --error "$b"; code 0
  [ -n "$s" ] && [ "$s" = "$out" ] && ok || bad "two signatures: [$s] [$out]"
  local x; out="$s"; for x in "$@"; do hasnt "$x"; done; }
fresh "signature: a quoted Windows path with a space is one path token, its tail and the user's name gone"
same "can't open \"C:\\Users\\John Smith\\a.txt\": denied" "can't open \"C:\\Users\\Ann Lee\\b.txt\": denied" \
  John john Smith smith Lee lee a.txt b.txt
has "denied"
fresh "signature: a single-quoted path with a space (Program Files) is one path token"
same "cannot run 'C:\\Program Files\\Git\\bin\\bash.exe': not found" "cannot run 'D:\\Tools\\Git\\bin\\bash.exe': not found" \
  program files tools bash.exe '\bin'
has "not found"
fresh "signature: a quoted POSIX path with a space is one path token"
same 'cannot open "/home/john smith/x": denied' 'cannot open "/home/ann lee/y": denied' john smith lee
has "denied"
fresh "signature: a UNC path with a \$ share and a space is one path token"
same 'cannot read \\srv01\builds$\a b\x.log: denied' 'cannot read \\other\share\c d\y.log: denied' \
  srv01 builds other share x.log y.log 'b\' 'd\' denied
has "cannot read"
fresh "signature: an scp-style remote is one token - no account, repository or host"
same "failed to push some refs to 'git@github.com:acme/shop.git'" "failed to push some refs to 'git@gitlab.com:x/y.git'" \
  acme shop github.com gitlab.com shop.git y.git
has "failed to push some refs to"
fresh "signature: user@host:/path is one token - no user, host or folder"
sig --source scripts/run-stats.sh --step deploy --exit 1 --error "cannot reach user@host:/srv/app now"; code 0
hasnt user; hasnt host; hasnt srv; hasnt app; has "cannot reach"; hasnt "now"
fresh "signature: not over-normalized - another verb, another signature"
sig --source scripts/run-stats.sh --step st --exit 1 --error "cannot open file"; code 0; s1="$out"
sig --source scripts/run-stats.sh --step st --exit 1 --error "cannot read file"; code 0
[ -n "$s1" ] && [ "$s1" != "$out" ] && ok || bad "one signature for two errors: [$s1] [$out]"
fresh "signature: not over-normalized - another --source, another signature"
sig --source scripts/a.sh --step st --exit 1 --error "cannot open file"; code 0; s1="$out"
sig --source scripts/b.sh --step st --exit 1 --error "cannot open file"; code 0
[ -n "$s1" ] && [ "$s1" != "$out" ] && ok || bad "one signature for two sources: [$s1] [$out]"
case "$s1" in "scripts/a.sh: "*) ok ;; *) bad "the source is not kept: [$s1]" ;; esac
fresh "signature: a negative exit code (a Windows crash) is accepted and kept as exit -1073741819"
sig --source scripts/run-stats.sh --step st --exit -1073741819 --error "the process crashed"; code 0
has "scripts/run-stats.sh: st: exit -1073741819: the process crashed"

# --- signature, round 4 of #338: safe by default - it goes to a public issue ---
# An unquoted path takes the rest of the line (a space in it cannot be told from words; nothing after its
# start reaches the issue); Windows relative and home paths; a backtick-quoted path and a quoted file:// URL
# with a space; e-mails and user@host; bare host names. The words before them stay.
fresh "signature: after an unquoted Windows path start the rest of the line is gone (OneDrive - Acme Corp)"
same 'run-stats: cannot read C:\Users\jo\OneDrive - Acme Corp\Documents\dev\shop\runs.tsv' 'run-stats: cannot read D:\work\runs.tsv' \
  acme corp shop documents
has "cannot read"
fresh "signature: after an unquoted POSIX path start the rest of the line is gone (Mobile Documents)"
sig --source scripts/run-stats.sh --step "read the run log" --exit 1 --error 'cannot read /Users/jo/Library/Mobile Documents/com~apple~CloudDocs/acme-shop/runs.tsv'; code 0
for x in acme mobile documents clouddocs; do hasnt "$x"; done; has "cannot read"
fresh "signature: after an unquoted POSIX path start the rest of the line is gone (GoogleDrive-jo@acme.com/My Drive)"
sig --source scripts/run-stats.sh --step "read the run log" --exit 1 --error 'cannot read /Users/jo/GoogleDrive-jo@acme.com/My Drive/acme-shop/runs.tsv'; code 0
for x in acme drive; do hasnt "$x"; done; has "cannot read"
fresh "signature: a path in parentheses with a space - the rest of the line is gone"
sig --source scripts/run-stats.sh --step "read the run log" --exit 1 --error 'cannot read the log (/home/jo smith/acme/x)'; code 0
for x in acme smith; do hasnt "$x"; done; has "cannot read the log"
fresh "signature: Windows relative and home paths - ..\\, .\\ and ~\\ are paths"
sig --source scripts/run-stats.sh --step build --exit 1 --error 'cannot run ..\acme-shop\build.ps1'; code 0
hasnt acme; hasnt build.ps1; has "cannot run"
sig --source scripts/run-stats.sh --step build --exit 1 --error 'cannot open .\acme-shop\x'; code 0
hasnt acme; has "cannot open"
sig --source scripts/run-stats.sh --step build --exit 1 --error 'cannot open ~\Documents\Acme Corp\x.txt'; code 0
hasnt acme; hasnt corp; hasnt documents; has "cannot open"
fresh "signature: a backtick-quoted path with a space is one path token"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'cannot open `/home/jo smith/x`'; code 0
hasnt smith; has "cannot open"
fresh "signature: a quoted file:// URL with a space is one URL token"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'cannot open "file:///C:/Users/Jo Smith/acme/x"'; code 0
hasnt smith; hasnt acme; has "cannot open"
fresh "signature: an e-mail in git's auto-detect message - no user, host or machine name"
sig --source scripts/run-stats.sh --step commit --exit 128 --error "fatal: unable to auto-detect email address (got 'jo@DESKTOP-ACME7.(none)')"; code 0
for x in jo acme desktop; do hasnt "$x"; done; has "unable to auto-detect email address"
fresh "signature: a bare e-mail address - no name or domain"
sig --source scripts/run-stats.sh --step push --exit 1 --error 'committer jo.smith@acme.com not allowed'; code 0
for x in jo smith acme; do hasnt "$x"; done; has "committer"; has "not allowed"
fresh "signature: Name <e-mail> - no name or domain"
sig --source scripts/run-stats.sh --step push --exit 1 --error 'Author: Jo Smith <jo@acme.com>'; code 0
for x in jo smith acme; do hasnt "$x"; done
fresh "signature: bare host names are a token - no company or service name"
sig --source scripts/run-stats.sh --step fetch --exit 128 --error 'ssh: Could not resolve hostname git.acme.internal: unknown'; code 0
hasnt acme; has "could not resolve hostname"; has "unknown"
sig --source scripts/run-stats.sh --step fetch --exit 255 --error 'ssh: connect to host gitlab.acme.com port 22: timed out'; code 0
hasnt acme; hasnt gitlab; has "connect to host"; has "timed out"
fresh "signature: a core file name with a dot and a version are no host (guard)"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'start-worker.sh needs CORE.md from core 2.1.310'; code 0
has "start-worker.sh"; has "core.md"; has "N.N.N"
fresh "signature: not over-normalized - two messages from the same source and step still differ"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'cannot read C:\Users\jo\a.txt'; code 0; s1="$out"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'cannot write C:\Users\jo\a.txt'; code 0
[ -n "$s1" ] && [ "$s1" != "$out" ] && ok || bad "one signature for two errors: [$s1] [$out]"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'push rejected for jo@acme.com'; code 0; s1="$out"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'fetch rejected for jo@acme.com'; code 0
[ -n "$s1" ] && [ "$s1" != "$out" ] && ok || bad "one signature for two errors: [$s1] [$out]"

# --- signature, round 5 of #338: any word with a / or \ is a token, core paths kept, versions and ports ---
# A word holding / or \ (a repository, a branch, a relative path, an env-variable or home path, a drive
# without a slash) is one token, unless it is a core path; the message words around it stay.
# word <error> <words around...> -- <names...>: one signature; the words around kept, none of the names
word() {
  local e="$1" x; shift
  sig --source scripts/run-stats.sh --step st --exit 1 --error "$e"; code 0
  while [ $# -gt 0 ] && [ "$1" != -- ]; do has "$1"; shift; done
  [ $# -gt 0 ] && shift
  for x in "$@"; do hasnt "$x"; done; }
fresh "signature: a repository owner/name in a git remote message is a token"
word 'remote: Permission to acme/shop.git denied' "permission to" -- acme shop
word "fatal: repository 'acme/shop' not found" "repository" "not found" -- acme shop
fresh "signature: a branch name with a slash is a token, the words after it stay"
word 'REMOVE FAILED: git branch -d feature/acme-login - left as is' "remove failed" "left as is" -- acme login
word "error: pathspec 'feature/acme-login' did not match" "pathspec" "did not match" -- acme login
fresh "signature: a relative path is a token"
word 'error: open src/acme/config.json' "error: open" -- acme config
fresh "signature: a Windows path without a drive, an env-variable path, a drive with no slash, ~user - tokens"
word 'cannot read Users\jo\acme\x' "cannot read" -- acme jo users
word 'cannot read %USERPROFILE%\acme\x' "cannot read" -- acme userprofile
word 'cannot read $HOME/acme/x' "cannot read" -- acme home
word 'cannot read D:acme\x' "cannot read" -- acme
word 'cannot read ~jo/acme/x' "cannot read" -- acme jo
fresh "signature: a word with a slash is a token in the middle of a line, the words after it stay"
word 'branch feature/acme-login is not merged' "branch" "is not merged" -- acme login
fresh "signature: core paths stay as written, lower-cased (guard)"
word 'cannot run scripts/start-worker.sh now' "cannot run scripts/start-worker.sh now" -- PATH HOST
word 'see procedures/CORE-FINDINGS.md first' "see procedures/core-findings.md first" -- PATH HOST
word 'see roles/worker.md first' "see roles/worker.md first" -- PATH HOST
word 'see skills/coord-retro/SKILL.md first' "see skills/coord-retro/skill.md first" -- PATH HOST
word 'tests/retro/run.sh failed' "tests/retro/run.sh failed" -- PATH HOST
fresh "signature: the coordinator's own files stay as written, lower-cased (guard)"
word 'cannot read PROJECT.md' "cannot read project.md" -- PATH HOST
word 'cannot read BINDINGS.md' "cannot read bindings.md" -- PATH HOST
word 'cannot append LOG.md' "cannot append log.md" -- PATH HOST
word 'cannot append RUNS.tsv' "cannot append runs.tsv" -- PATH HOST
word 'cannot read CHECKLIST.md' "cannot read checklist.md" -- PATH HOST
fresh "signature: cannot read PROJECT.md and cannot read BINDINGS.md - two signatures"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'cannot read PROJECT.md'; code 0; s1="$out"
sig --source scripts/run-stats.sh --step st --exit 1 --error 'cannot read BINDINGS.md'; code 0
[ -n "$s1" ] && [ "$s1" != "$out" ] && ok || bad "one signature for two files: [$s1] [$out]"
fresh "signature: v2.1.310 and 2.1.310 - one token"
same 'needs core v2.1.310 or later' 'needs core 2.1.310 or later' 310
has "needs core"; has "or later"
fresh "signature: e.g. stays e.g. - no host"
word 'set the model, e.g. opus' "set the model, e.g. opus" -- HOST
fresh "signature: an IP address with a port - one token, whatever the port"
same 'cannot connect to 10.1.2.3:8443 now' 'cannot connect to 10.9.9.9:22 now' 8443 '10.'
has "cannot connect to"; has "now"

# --- file ---
fresh "FIXED UPSTREAM: the exact signature on an issue closed as completed -> exit 3, nothing filed"
printf '55\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused"
code 3; has "FIXED UPSTREAM #55"; count create 0; count reaction 0; count comment 0; readonly_else

fresh "closed as not planned is no fix: the keyword search goes on, CHECK"
printf '56\tCLOSED\tNOT_PLANNED\tmerge-queue: the refused update\n' > "$STUB_D/exact"
printf '11\tOPEN\t\tmerge queue stops on a refused update\n' > "$STUB_D/keyword"
file --keywords "merge-queue update refused"
code 4; hasnt "FIXED UPSTREAM"; has "CHECK"; has "#11"; count create 0; readonly_else

fresh "REPEAT: the signature on an open issue -> one +1 reaction, no comment, nothing filed"
printf '77\tOPEN\t\tmerge-queue: the refused update\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused"
code 0; has "REPEAT #77"; count reaction 1; count create 0; count comment 0; readonly_else
grep -q 'issues/77/reactions' "$STUB_D/log" && grep -qF -- 'content=+1' "$STUB_D/log" && ok || { bad "no content=+1 reaction on #77"; sed 's/^/    log: /' "$STUB_D/log"; }

fresh "REPEAT with the reaction already there from this account: the same line, no POST"
printf '77\tOPEN\t\tmerge-queue: the refused update\n' > "$STUB_D/exact"
printf '+1\tsomeone-else\n+1\tstub-user\n' > "$STUB_D/reactions-77"
file --keywords "merge-queue update refused"
code 0; has "REPEAT #77"; count reaction 0; count create 0; count comment 0; readonly_else

fresh "REPEAT, another account's reaction only: this account adds its own"
printf '77\tOPEN\t\tmerge-queue: the refused update\n' > "$STUB_D/exact"
printf '+1\tsomeone-else\nheart\tstub-user\n' > "$STUB_D/reactions-77"
file --keywords "merge-queue update refused"
code 0; has "REPEAT #77"; count reaction 1; count create 0

fresh "REPEAT with --comment-file: the reaction and one comment with that text"
printf '77\tOPEN\t\tmerge-queue: the refused update\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused" --comment-file "$COMMENT"
code 0; has "REPEAT #77"; count reaction 1; count comment 1; count create 0; readonly_else
grep -qE '^issue comment( .*)? 77( |$)' "$STUB_D/log" && grep -qF 'macOS 15' "$STUB_D/commented" 2>/dev/null && ok || { bad "no comment on #77 with the file's text"; sed 's/^/    log: /' "$STUB_D/log"; }

fresh "CHECK: candidates not in --checked -> exit 4, every candidate and its title printed, nothing filed"
printf '11\tOPEN\t\tmerge queue stops on a refused update\n12\tCLOSED\tCOMPLETED\tupdate-branch refused by GitHub\n' > "$STUB_D/keyword"
file --keywords "merge-queue update refused"
code 4; has "CHECK"; has "#11"; has "#12"; has "merge queue stops on a refused update"; has "update-branch refused by GitHub"
count create 0; count reaction 0; count comment 0; readonly_else
grep -q '^issue list .*--state all' "$STUB_D/log" && grep -F 'merge-queue update refused' "$STUB_D/log" | grep -qvF "$SIG" && ok ||
  { bad "no keyword search over open and closed issues with the keywords"; sed 's/^/    log: /' "$STUB_D/log"; }

fresh "CHECK: one candidate checked, one not -> still exit 4 naming the unchecked one"
printf '11\tOPEN\t\tmerge queue stops on a refused update\n12\tCLOSED\tCOMPLETED\tupdate-branch refused by GitHub\n' > "$STUB_D/keyword"
file --keywords "merge-queue update refused" --checked 11
code 4; has "#12"; count create 0

fresh "CHECK: six candidates -> at most 5"
for i in 21 22 23 24 25 26; do printf '%s\tOPEN\t\tcandidate number %s\n' $i $i; done > "$STUB_D/keyword"
file --keywords "merge-queue update refused"
code 4; has "#21"; has "#25"; hasnt "#26"; count create 0

fresh "FILED: no candidates -> one issue, the body ends with its Signature line"
file --keywords "merge-queue update refused"
code 0; has "FILED #901"; count create 1; count reaction 0; count comment 0; readonly_else
c="$(tr -d '\r' 2>/dev/null < "$STUB_D/created")"
printf '%s\n' "$c" | grep -qF 'Steps: land 12 on a behind PR.' && ok || bad "the body file's text is not in the issue"
[ "$(printf '%s\n' "$c" | sed '/^$/d' | tail -n 1)" = "Signature: $SIG" ] && ok || bad "the body's last line is not Signature: <sig>: $(printf '%s\n' "$c" | tail -n 1)"
printf '%s\n' "$c" | grep -q '^Checked:' && bad "a Checked line with no candidates" || ok
grep -q "^issue create .*--repo $R" "$STUB_D/log" && ok || { bad "issue create not in $R"; sed 's/^/    log: /' "$STUB_D/log"; }

fresh "FILED: all candidates checked -> one issue naming them in Checked: #a, #b"
printf '11\tOPEN\t\tmerge queue stops on a refused update\n12\tCLOSED\tCOMPLETED\tupdate-branch refused by GitHub\n' > "$STUB_D/keyword"
echo 905 > "$STUB_D/next"
file --keywords "merge-queue update refused" --checked 11,12
code 0; has "FILED #905"; hasnt "CHECK"; count create 1; count reaction 0; readonly_else
c="$(tr -d '\r' 2>/dev/null < "$STUB_D/created")"
printf '%s\n' "$c" | grep -qxF 'Checked: #11, #12' && ok || bad "no line Checked: #11, #12 in the body"
[ "$(printf '%s\n' "$c" | sed '/^$/d' | tail -n 1)" = "Signature: $SIG" ] && ok || bad "the body's last line is not Signature: <sig>"

fresh "--dry-run, a new issue: what it would file printed, no create, reaction or comment"
file --keywords "merge-queue update refused" --dry-run
code 0; has "$SIG"; count create 0; count reaction 0; count comment 0; readonly_else

fresh "--dry-run, a repeat with --comment-file: the issue named, no reaction or comment"
printf '77\tOPEN\t\tmerge-queue: the refused update\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused" --comment-file "$COMMENT" --dry-run
code 0; has "#77"; count create 0; count reaction 0; count comment 0; readonly_else

# --- an open match first; --regression (round 2 of #338) ---
fresh "an open issue wins over a closed one: both hold the signature -> REPEAT the open one, never FIXED UPSTREAM"
printf '55\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n77\tOPEN\t\tmerge-queue: the refused update again\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused"
code 0; has "REPEAT #77"; hasnt "FIXED UPSTREAM"; count reaction 1; count create 0; count comment 0; readonly_else
grep -q 'issues/77/reactions' "$STUB_D/log" && ok || { bad "no reaction on #77"; sed 's/^/    log: /' "$STUB_D/log"; }

fresh "--regression, only a closed-as-completed match -> one new issue: Regression of #55, the Signature line last"
printf '55\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused" --regression
code 0; has "FILED #901"; hasnt "FIXED UPSTREAM"; count create 1; count reaction 0; count comment 0; readonly_else
c="$(tr -d '\r' 2>/dev/null < "$STUB_D/created")"
printf '%s\n' "$c" | grep -qE '^Regression of #55([^0-9]|$)' && ok || bad "no line Regression of #55 in the body"
printf '%s\n' "$c" | grep -qF 'Steps: land 12 on a behind PR.' && ok || bad "the body file's text is not in the issue"
[ "$(printf '%s\n' "$c" | sed '/^$/d' | tail -n 1)" = "Signature: $SIG" ] && ok || bad "the body's last line is not Signature: <sig>"
grep -qE -- '^issue create .*--title merge-queue stops when the update is refused( --|$)' "$STUB_D/log" && ok ||
  { bad "issue create without the title as given"; sed 's/^/    log: /' "$STUB_D/log"; }
grep -q 'issues/55' "$STUB_D/log" && { bad "a call on #55"; sed 's/^/    log: /' "$STUB_D/log"; } || ok

fresh "--regression with an open match too -> REPEAT the open one, nothing filed"
printf '55\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n78\tOPEN\t\tRegression: merge-queue stops again\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused" --regression
code 0; has "REPEAT #78"; hasnt "FIXED UPSTREAM"; hasnt "FILED"; count reaction 1; count create 0; count comment 0; readonly_else

fresh "--regression, no exact match, candidates -> CHECK as without it"
printf '11\tOPEN\t\tmerge queue stops on a refused update\n' > "$STUB_D/keyword"
file --keywords "merge-queue update refused" --regression
code 4; has "CHECK"; has "#11"; count create 0; count reaction 0; readonly_else

fresh "--regression, no exact match, no candidates -> FILED as without it, no Regression line"
file --keywords "merge-queue update refused" --regression
code 0; has "FILED #901"; count create 1; count reaction 0; readonly_else
c="$(tr -d '\r' 2>/dev/null < "$STUB_D/created")"
printf '%s\n' "$c" | grep -q '^Regression of' && bad "a Regression line with no closed match" || ok
[ "$(printf '%s\n' "$c" | sed '/^$/d' | tail -n 1)" = "Signature: $SIG" ] && ok || bad "the body's last line is not Signature: <sig>"

fresh "--regression --dry-run, a closed match: the would-be filing printed naming #55, no write"
printf '55\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused" --regression --dry-run
code 0; has "#55"; has "$SIG"; hasnt "FIXED UPSTREAM"; count create 0; count reaction 0; count comment 0; readonly_else

# --- the newest fix (round 4 of #338) ---
fresh "FIXED UPSTREAM: two closed-as-completed matches #12 and #80 -> the newest fix, #80"
printf '12\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n80\tCLOSED\tCOMPLETED\tmerge-queue: the refused update again\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused"
code 3; has "FIXED UPSTREAM #80"; hasnt "#12"; count create 0; count reaction 0; count comment 0; readonly_else

fresh "--regression, two closed-as-completed matches #12 and #80 -> Regression of #80"
printf '12\tCLOSED\tCOMPLETED\tmerge-queue: the refused update\n80\tCLOSED\tCOMPLETED\tmerge-queue: the refused update again\n' > "$STUB_D/exact"
file --keywords "merge-queue update refused" --regression
code 0; has "FILED #901"; count create 1; count reaction 0; count comment 0; readonly_else
c="$(tr -d '\r' 2>/dev/null < "$STUB_D/created")"
printf '%s\n' "$c" | grep -qE '^Regression of #80([^0-9]|$)' && ok || bad "no line Regression of #80 in the body: $(printf '%s\n' "$c" | grep '^Regression' )"

echo "report-issue ($kind): $((pass + fail)) checks, $([ $fail = 0 ] && echo "all pass" || echo "$fail FAILED")"
[ $fail = 0 ]

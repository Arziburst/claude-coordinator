#!/usr/bin/env bash
# Tests for scripts/hooks/net-guard.{sh,ps1} (#380). Usage: run.sh sh | run.sh ps <powershell|pwsh>
# ACCESS POINTS the worker implements as written (a test never guesses at internals):
#  - input: the hook JSON on stdin, {"tool_input":{"command":"..."}} (as safety-guard reads it)
#  - setting: env COORD_ASSISTANT_HOSTS=<host>[:write],...  (unset or empty = every client call blocked)
#  - verdict: exit 0 = allowed, exit 2 = blocked; on a block stderr names COORD_ASSISTANT_HOSTS
#  - no options: the script is run bare, no arguments
# Case line: expected exit @@ list ('-' = unset, '=' = empty) @@ command
# Known limit (last case): a client's name in a quoted string blocks (fails closed).
cd "$(dirname "$0")/../.." || exit 1
mode="${1:-sh}"
case "$mode" in
  sh) run() { bash scripts/hooks/net-guard.sh; } ;;
  ps) exe="${2:-pwsh}"; run() { "$exe" -NoProfile -File scripts/hooks/net-guard.ps1; } ;;
  *) echo "usage: run.sh sh | ps <powershell|pwsh>"; exit 1 ;;
esac
pass=0; fail=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  exp=${line%% @@ *}; rest=${line#* @@ }; list=${rest%% @@ *}; cmd=${rest#* @@ }
  j=${cmd//\\/\\\\}; j=${j//\"/\\\"}
  case "$list" in -) unset COORD_ASSISTANT_HOSTS ;; =) export COORD_ASSISTANT_HOSTS= ;; *) export COORD_ASSISTANT_HOSTS="$list" ;; esac
  err=$(printf '{"tool_input":{"command":"%s"}}' "$j" | run 2>&1 >/dev/null); got=$?
  if [ "$got" = "$exp" ] && { [ "$exp" != 2 ] || case "$err" in *COORD_ASSISTANT_HOSTS*) true ;; *) false ;; esac; }; then
    pass=$((pass+1))
  else fail=$((fail+1)); echo "FAIL want=$exp got=$got list=[$list] cmd: $cmd"; echo "   ${err%%$'\n'*}"; fi
done <<'CASES'
0 @@ - @@ ls -la
0 @@ - @@ git status
2 @@ - @@ curl https://api.example.com/x
2 @@ = @@ curl https://api.example.com/x
0 @@ api.example.com @@ curl https://api.example.com/v1/items
2 @@ api.example.com @@ curl https://api.example.com.evil.org/x
2 @@ api.example.com @@ curl https://evil.org/api.example.com
2 @@ api.example.com @@ curl https://api.example.com@evil.org/
0 @@ API.Example.COM @@ curl https://API.EXAMPLE.com/x
0 @@ api.example.com @@ curl https://api.example.com:8443/x
2 @@ api.example.com @@ curl https://user:pw@api.example.com/x
2 @@ api.example.com @@ curl -d a=b https://api.example.com/x
0 @@ api.example.com:write @@ curl -d a=b https://api.example.com/x
2 @@ api.example.com @@ curl -X POST https://api.example.com/x
0 @@ api.example.com @@ curl -X GET https://api.example.com/x
0 @@ api.example.com:write @@ curl -X POST https://api.example.com/x
0 @@ api.example.com:write @@ curl https://api.example.com/x
2 @@ api.example.com @@ curl --json {} https://api.example.com/x
2 @@ api.example.com @@ curl -F f=@a https://api.example.com/x
2 @@ api.example.com @@ curl -T file https://api.example.com/x
2 @@ api.example.com @@ curl $URL
2 @@ api.example.com @@ curl https://$H/x
2 @@ api.example.com @@ curl $(cat u)
2 @@ api.example.com @@ curl
2 @@ api.example.com @@ curl -K cfg https://api.example.com/x
2 @@ api.example.com @@ curl --config cfg https://api.example.com/x
0 @@ - @@ curl --help
0 @@ - @@ curl -h
2 @@ api.example.com @@ curl https://api.example.com/a https://evil.org/b
0 @@ api.example.com,other.example.org @@ curl https://api.example.com/a https://other.example.org/b
0 @@ api.example.com @@ wget https://api.example.com/f
2 @@ api.example.com @@ wget --post-data=a=b https://api.example.com/
0 @@ api.example.com @@ curl.exe https://api.example.com/
2 @@ api.example.com @@ curl.exe https://evil.org/
0 @@ api.example.com @@ Invoke-WebRequest -Uri https://api.example.com/x
2 @@ api.example.com @@ iwr https://evil.org/x
2 @@ api.example.com @@ Invoke-RestMethod -Method Post -Body x -Uri https://api.example.com/
0 @@ api.example.com:write @@ irm -Method Post -Body x -Uri https://api.example.com/
2 @@ api.example.com @@ Invoke-WebRequest -InFile f -Uri https://api.example.com/
2 @@ api.example.com @@ echo "curl is a tool"
CASES
echo "net-guard ($mode): $pass passed, $fail failed"; [ "$fail" = 0 ]

#!/usr/bin/env bash
# Optional second PreToolUse hook for an assistant's session (#380, TOOLKIT.md *Assistants*): beside
# safety-guard, connected only in the settings of a session that needs it. Reads the tool call JSON on
# stdin; exit 2 blocks. A command naming a network client (curl, wget, Invoke-WebRequest, iwr,
# Invoke-RestMethod, irm, also .exe) may reach only http(s) hosts listed in COORD_ASSISTANT_HOSTS=
# <host>[:write],... (exact host, any case, port ignored, no user part); data / write forms (-d, --data*,
# -F, -T, -X other than GET, --json, -Method other than Get, -Body, -InFile, --post-*) need :write. An
# address it cannot read (variable, substitution, none), -K / --config: blocked. --help / -h allowed.
# Unset or empty list: every client call blocked. A command with no client word passes at once.
# NOT A WALL: it reads text, no shell parse. A client's name inside a quoted string may block (fails
# closed), also one that only names a client (grep curl file, git log --grep curl): refused, the way out
# is to read that file another way; a short-flag cluster (curl -sd x) is not read as data; .NET, scripts
# and other tools are out of reach (no wall: #375). Same verdicts as net-guard.ps1.
j=$(cat)
echo "$j" | grep -qiE "(^|[^A-Za-z0-9_.-])(curl|wget|invoke-webrequest|iwr|invoke-restmethod|irm)(\.exe)?([^A-Za-z0-9_-]|$)" || exit 0
echo "$j" | grep -qE '(^|[[:space:]])(-h|--help)([[:space:]"]|\\|$)' && exit 0
no() { echo "net-guard: $1 (allowed hosts: COORD_ASSISTANT_HOSTS=<host>[:write],...)" >&2; exit 2; }
echo "$j" | grep -qE '(^|[[:space:]])(-K|--config)([[:space:]=]|$)' && no "a config file cannot be read"
w=0
echo "$j" | grep -qE '(^|[[:space:]])(-d|-F|-T|--data[a-z-]*|--form|--upload-file|--json|--post-[a-z]*)([[:space:]=]|\\|$)' && w=1
echo "$j" | grep -qiE '(^|[[:space:]])(-Body|-InFile)([[:space:]]|\\|$)' && w=1
m=$(echo "$j" | grep -oiE '(^|[[:space:]])(-X|-Method|--request)[ =]*[A-Za-z]+' | head -n1 | tr 'A-Z' 'a-z' | sed -E 's/^.*(-x|-method|--request)[ =]*//')
[ -n "$m" ] && [ "$m" != get ] && w=1
urls=$(echo "$j" | grep -oiE "https?://[^[:space:]\"'\\\\<>|;&)]*")
[ -n "$urls" ] || no "no address it can read"
list=$(printf '%s' "${COORD_ASSISTANT_HOSTS:-}" | tr 'A-Z' 'a-z')
while IFS= read -r u; do
  h=${u#*://}; h=${h%%[/?#]*}
  case "$h" in *@*) no "user part in $u" ;; esac
  h=$(printf %s "${h%%:*}" | tr A-Z a-z)
  ok=0
  for e in ${list//,/ }; do
    [ "${e%:write}" = "$h" ] || continue
    if [ "$w" = 1 ] && [ "$e" = "${e%:write}" ]; then continue; fi
    ok=1
  done
  [ "$ok" = 1 ] || no "$u is not allowed (a write form needs :write)"
done <<< "$urls"
exit 0

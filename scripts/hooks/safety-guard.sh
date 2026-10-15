#!/usr/bin/env bash
# PreToolUse safety hook for coordinator projects (Bash / PowerShell tools; with COORD_PROTECTED_ROOT
# set, also Edit / Write / MultiEdit / NotebookEdit: no edit under that folder outside its
# .claude/worktrees/ - the owner's working copy, TOOLKIT.md *Safety*).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only — the real enforcement is branch protection on the code host (CORE §2); deliberate
# obfuscation (eval, quoting tricks, aliases ...) is out of scope (TOOLKIT.md *Safety*).
# Extra project patterns (one extended regex per line, '#' comments; a pattern that cannot be read
# blocks every call): .claude/coordinator-deny.txt
# Self-test: scripts/hooks/safety-guard.sh --self-test   (prints to stdout so the session sees it)
# Works on macOS (bash 3.2, BSD awk / sed), Linux and Windows (Git Bash); jq is used when present.
# Same rules as safety-guard.ps1, both checked against tests/safety-guard/cases.txt.

# The protected branches: COORD_PROTECTED_BRANCHES, names separated by spaces and/or commas (TOOLKIT.md
# *Safety*); each is compared whole and literally (no patterns: . + * / are plain characters), letter
# case ignored. Empty or unset: main master.
prot=(); pbs="${COORD_PROTECTED_BRANCHES:-}"
set -f; for b in ${pbs//,/ }; do prot+=("$b"); done; set +f
[ ${#prot[@]} -gt 0 ] || prot=(main master)

if [ "${1:-}" = "--self-test" ]; then
  # a push to the first protected branch (main by default) must block (exit 2) and a work-branch push
  # must pass (exit 0): a guard that blocks everything (a syntax error also exits 2) is not working either
  out=$(printf '{"tool_input":{"command":"git push --force origin %s"}}' "${prot[0]}" | bash "$0" 2>/dev/null; echo $?)
  ok=$(printf '%s' '{"tool_input":{"command":"git push origin 12-fix"}}' | bash "$0" 2>/dev/null; echo $?)
  if [ "$out" = "2" ] && [ "$ok" = "0" ]; then echo "safety-guard: OK"; exit 0; fi
  echo "safety-guard: NOT WORKING — STOP: do not start workers until it is fixed (TOOLKIT.md)."
  exit 0   # stdout reaches the session's context; a non-zero exit would only show it to the user
fi

input="$(cat)"
# A BOM (or anything else) before the JSON object is dropped. Input that is not a JSON object blocks:
# Claude Code always sends one, and a guard that cannot read the call must not let it through.
case "$input" in '{'*) ;; *'{'*) input="{${input#*\{}" ;; esac
unreadable() {
  echo "Blocked by safety-guard: the tool call could not be read (not a JSON object). If this is a false positive, ask the owner." >&2
  exit 2
}
case "$(printf '%s' "$input" | tr -d ' \t\r\n')" in '{'*'}') ;; *) unreadable ;; esac
nl=$'\n'; cr=$'\r'; tab=$'\t'

# Extract tool_input.command and cwd: jq if present, otherwise a small JSON reader in awk that walks
# the whole object (so only tool_input's own "command" counts, and what is not JSON blocks) and decodes
# the strings' escapes (linear, so a long heredoc stays fast with BSD awk).
JSON_AWK='
function ws() { while (i <= n && index(" \t\r\n", substr(s, i, 1))) i++ }
# a string at i: moves i past it and returns its raw body (escapes kept), or "\001" when it is not one
function str(    r) {
  r = substr(s, i)
  if (!match(r, /^"([^"\\]|\\.)*"/)) return "\001"
  i += RLENGTH; return substr(r, 2, RLENGTH - 2)
}
# the decoded text of a short raw string (keys)
function dec(x,    m, P, k, p, c, o) {
  m = split(x, P, "\\"); o = P[1]
  for (k = 2; k <= m; k++) {
    p = P[k]
    if (p == "") { o = o "\\"; k++; if (k <= m) o = o P[k]; continue }
    c = substr(p, 1, 1); if (c == "u") c = "?"; o = o c substr(p, (c == "?") ? 6 : 2)
  }
  return o
}
# prints the decoded text of a raw string piece by piece (no long concatenations)
function emit(all, ol,    m, P, i, p, c, r, v, h, k) {
  m = split(all, P, "\\"); printf "%s", P[1]
  for (i = 2; i <= m; i++) {
    p = P[i]
    if (p == "") { printf "\\"; i++; if (i <= m) printf "%s", P[i]; continue }
    c = substr(p, 1, 1); r = substr(p, 2)
    if (c == "n") c = ol ? " " : "\n"; else if (c == "t") c = "\t"; else if (c == "r") c = ol ? " " : "\r"; else if (c == "b" || c == "f") c = " "
    else if (c == "u") {
      v = 0; h = tolower(substr(p, 2, 4)); r = substr(p, 6)
      for (k = 1; k <= 4; k++) v = v * 16 + index("0123456789abcdef", substr(h, k, 1)) - 1
      c = (v > 0 && v < 128) ? sprintf("%c", v) : "?"
    }
    printf "%s%s", c, r
  }
}
# one JSON value at i; path is the keys leading to it. Returns 0 when the text is not JSON.
function val(path,    c, k) {
  ws(); c = substr(s, i, 1)
  if (c == "{" || c == "[") {
    i++; ws()
    if (substr(s, i, 1) == ((c == "{") ? "}" : "]")) { i++; return 1 }
    while (1) {
      if (c == "{") {
        ws(); if (substr(s, i, 1) != "\"") return 0
        k = str(); if (k == "\001") return 0
        ws(); if (substr(s, i, 1) != ":") return 0
        i++; if (!val(path SUBSEP dec(k))) return 0
      } else if (!val(path SUBSEP "[]")) return 0
      ws(); k = substr(s, i, 1); i++
      if (k == ((c == "{") ? "}" : "]")) return 1
      if (k != ",") return 0
    }
  }
  if (c == "\"") {
    k = str(); if (k == "\001") return 0
    if (path == SUBSEP "tool_input" SUBSEP "command") CMD = k
    else if (path == SUBSEP "cwd") CWD = k
    else if (path == SUBSEP "tool_name") TOOL = k
    else if (path == SUBSEP "tool_input" SUBSEP "file_path") FP = k
    else if (path == SUBSEP "tool_input" SUBSEP "notebook_path") NP = k
    else if (path == SUBSEP "tool_input" SUBSEP "to") TO = k
    return 1
  }
  if (match(substr(s, i, 64), /^(-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)/)) { i += RLENGTH; return 1 }
  return 0
}
{ all = (NR > 1) ? all "\n" $0 : $0 }
END {
  s = all; n = length(s); i = 1; CMD = ""; CWD = ""; TOOL = ""; FP = ""; NP = ""; TO = ""
  ws(); if (substr(s, i, 1) != "{" || !val("")) exit 3
  ws(); if (i <= n) exit 3
  emit(CWD); printf "\n"; emit(TOOL); printf "\n"; emit(FP); printf "\n"; emit(NP); printf "\n"; emit(TO, 1); printf "\n"; emit(CMD); printf "."
}'
fp="" np="" to=""
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 || unreadable
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
  tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
  [ "$tool" = SendMessage ] && to=$(printf '%s' "$input" | jq -r '.tool_input.to // empty | strings | gsub("[\n\r]"; " ")' 2>/dev/null)
else
  both=$(printf '%s' "$input" | awk "$JSON_AWK") || unreadable
  both="${both%.}"; cwd="${both%%$nl*}"; both="${both#*$nl}"; tool="${both%%$nl*}"; both="${both#*$nl}"
  fp="${both%%$nl*}"; both="${both#*$nl}"; np="${both%%$nl*}"; both="${both#*$nl}"; to="${both%%$nl*}"; cmd="${both#*$nl}"
fi

# A path in one form for comparing (its canon form): / separators, none repeated or trailing, lower case
# (keep: the letter case kept), . and x/.. taken out (by the text: /a/b/.. is /a; .. above the root stays
# at the root), a drive as c: (C:\x, /c/x, /mnt/c/x and /cygdrive/c/x are all c:/x); / itself is empty.
# canon_core <path>: of a path already in / separators and in the letter case wanted (no forks)
canon_core() {
  local x="$1" r="" s out="" n=0 t IFS=/; local segs=()
  [ -n "$x" ] || return 0
  case "$x" in /*) r=/ ;; [A-Za-z]:*) r="${x:0:2}/"; x="${x:2}" ;; esac
  set -f; segs=($x); set +f   # split at / (no globbing: a * in the path stays a word)
  for s in "${segs[@]}"; do
    case "$s" in
      ''|.) ;;
      ..) if [ $n -gt 0 ] && [ "${out##*/}" != .. ]; then out="${out%/*}"; n=$((n - 1))
          elif [ -z "$r" ]; then out="$out/.."; n=$((n + 1)); fi ;;
      *) out="$out/$s"; n=$((n + 1)) ;;
    esac
  done
  x="$r${out#/}"; [ -z "$x" ] && x=.
  while :; do case "$x" in */) x="${x%/}" ;; *) break ;; esac; done
  # a drive in its Git Bash, WSL or Cygwin form: /c, /mnt/c, /cygdrive/c (and what follows) -> c:
  case "$x" in /mnt/?|/mnt/?/*) t="${x#/mnt/}" ;; /cygdrive/?|/cygdrive/?/*) t="${x#/cygdrive/}" ;; /?|/?/*) t="${x#/}" ;; *) t="" ;; esac
  case "$t" in [A-Za-z]|[A-Za-z]/*) x="${t%%/*}:${t#?}" ;; esac
  printf '%s' "$x"
}
# canon_all <keep or ""> <path>...: the canon form of each path, one per line (one tr for all of them)
canon_all() {
  local l
  while IFS= read -r l; do canon_core "$l"; printf '\n'; done <<CANON_ALL_END
$(case_fold "$@")
CANON_ALL_END
}
case_fold() {   # case_fold <keep or ""> <path>...: one per line, \ as /, lower case unless keep
  local m="$1"; shift
  if [ "$m" = keep ]; then printf '%s\n' "$@" | tr '\\' '/'; else printf '%s\n' "$@" | tr '\\A-Z' '/a-z'; fi
}
# A path as it lies on disk (#121): the part of it that exists, entered a folder at a time with cd -P
# (links - symlinks, junctions - resolved; .. after a link goes to the link target's parent, as the
# system takes it), then the rest as written. physical <keep or ""> <path>... prints one line per path:
# "." and its canon form (so / is "."), or an empty line when not even its start exists. One subshell for
# all the paths; a loop or a dangling link ends the existing part (cd -P fails), so nothing hangs. Git
# Bash: cd -P and pwd -P see through a junction; pwd -W gives the C:/... form.
case "${OSTYPE:-}" in msys*|cygwin*) pwdw=-W ;; *) pwdw=-P ;; esac   # Git Bash: msys (no fork for uname)
physical() {
  local a b
  while IFS= read -r a && IFS= read -r b; do
    a="${a#.}"; b="${b#.}"
    if [ -n "$a" ]; then printf .; canon_core "$a$b"; fi
    printf '\n'
  done <<PHYSICAL_END
$(physical_folded "$@")
PHYSICAL_END
}
physical_folded() {   # physical_folded <keep or ""> <path>...: physical_parts, in lower case unless keep
  local m="$1"; shift
  if [ "$m" = keep ]; then physical_parts "$@"; else physical_parts "$@" | tr 'A-Z' 'a-z'; fi
}
# two lines per path, each starting with "." (so none is empty): the physical folder, the rest; run in a
# subshell (it changes the directory). A folder at a time, not cd -P <whole path>: Git Bash takes .. in a
# C:/... path by the text, before the links.
physical_parts() {
  local p s rest start here i; local segs
  CDPATH=; here="$PWD"
  for p in "$@"; do
    p="${p//$nl/ }"; p="${p//\\//}"; rest=""
    case "$p" in /*) start=/ ;; [A-Za-z]:*) start="${p:0:2}/"; p="${p:2}" ;; *) start="$here" ;; esac
    if ! cd -P -- "$start" 2>/dev/null; then printf '.\n.\n'; continue; fi
    set -f; IFS=/ read -r -a segs <<PHYSICAL_PATH_END
$p
PHYSICAL_PATH_END
    set +f
    i=0
    for s in "${segs[@]}"; do
      i=$((i + 1))
      case "$s" in
        ''|.) continue ;;
        ..) case "$pwdw$PWD" in -W/|-W/[A-Za-z]) ;; *) cd -P .. 2>/dev/null ;; esac; continue ;;   # above a drive: stays
      esac
      [ -d "./$s" ] && cd -P -- "./$s" 2>/dev/null && continue
      rest="/$s"; while [ $i -lt ${#segs[@]} ]; do rest="$rest/${segs[$i]}"; i=$((i + 1)); done
      break
    done
    printf .; pwd $pwdw; printf '.%s\n' "$rest"
  done
}

# --- own sessions only (CORE §1.17): claude stop / rm / respawn / attach <id>, claude --resume <id> and
# the SendMessage tool are blocked for a session whose working folder is outside the project ---
# The sessions come from `claude agents --json --all`, read only for those calls; a session it does not
# list, or a listing that cannot be read, passes (nothing to tell it by). The project's folders:
# CLAUDE_PROJECT_DIR, the top of the repository the call works in and that repository's main checkout
# (their .claude/worktrees inside them), and the worktree roots of <folder>/coordinator/PROJECT.md
# (its Settings row "Worktree roots", as scripts/retro reads it); each as written and as it lies on disk,
# whole path segments compared (<root>-old is another folder), letter case ignored on Windows and macOS.
# AGENTS_AWK: four lines per session of the listing (id, sessionId, cwd, name), escapes decoded
AGENTS_AWK='
function dec(x,    o, c, k, h, v) {
  o = ""
  while ((k = index(x, "\\")) > 0) {
    o = o substr(x, 1, k - 1); c = substr(x, k + 1, 1); x = substr(x, k + 2)
    if (c == "u") { h = tolower(substr(x, 1, 4)); x = substr(x, 5); v = 0
      for (k = 1; k <= 4; k++) v = v * 16 + index("0123456789abcdef", substr(h, k, 1)) - 1
      c = (v > 31 && v < 128) ? sprintf("%c", v) : "?" }
    else if (c == "n" || c == "r" || c == "t" || c == "b" || c == "f") c = " "
    o = o c
  }
  return o x
}
{ all = (NR > 1) ? all "\n" $0 : $0 }
END {
  s = all; n = length(s); i = 1; dep = 0; key = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"") {
      r = substr(s, i); if (!match(r, /^"([^"\\]|\\.)*"/)) exit 3
      t = substr(r, 2, RLENGTH - 2); i += RLENGTH
      j = i; while (j <= n && index(" \t\r\n", substr(s, j, 1))) j++
      if (substr(s, j, 1) == ":") { key = (dep == 2) ? t : ""; i = j + 1; continue }
      if (dep == 2 && key != "") V[key] = dec(t)
      key = ""; continue
    }
    if (c == "{" || c == "[") { dep++; if (dep == 2) split("", V) }
    else if (c == "}" || c == "]") {
      if (dep == 2 && c == "}") printf "%s\n%s\n%s\n%s\n", V["id"], V["sessionId"], V["cwd"], V["name"]
      dep--
    } else if (c == ",") key = ""
    i++
  }
}'
agents_read=0; ag_ids=(); ag_sids=(); ag_cwds=(); ag_names=()
read_agents() {
  local raw a b c d
  [ $agents_read = 1 ] && return 0; agents_read=1
  command -v claude >/dev/null 2>&1 || return 0
  raw=$(claude agents --json --all 2>/dev/null) || return 0
  while IFS= read -r a && IFS= read -r b && IFS= read -r c && IFS= read -r d; do
    ag_ids+=("$a"); ag_sids+=("$b"); ag_cwds+=("$c"); ag_names+=("$d")
  done <<AGENTS_END
$(printf '%s' "$raw" | awk "$AGENTS_AWK")
AGENTS_END
}
case "${OSTYPE:-}" in msys*|cygwin*|darwin*) sm="" ;; *) sm=keep ;; esac   # letter case kept on Linux
owns_read=0; owns=()
own_forms() {
  local c out common r w l; local raw=() rel=()
  [ $owns_read = 1 ] && return 0; owns_read=1
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && raw+=("$CLAUDE_PROJECT_DIR")
  c="${cwd:-${CLAUDE_PROJECT_DIR:-}}"
  if [ -n "$c" ] && out=$(git -C "$c" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null); then
    raw+=("${out%%$nl*}")
    common="${out#*$nl}"
    case "$common" in */.git) raw+=("${common%/.git}") ;; esac
  fi
  for r in "${raw[@]}"; do
    [ -f "$r/coordinator/PROJECT.md" ] || continue
    r="$(printf '%s' "$r" | tr '\\' '/')"; r="${r%/}"
    while IFS= read -r w; do
      [ -n "$w" ] || continue
      w="$(printf '%s' "$w" | tr '\\' '/')"
      case "$w" in /*|[A-Za-z]:*) ;; *) w="$r/$w" ;; esac   # .. is taken out by the canon form
      rel+=("$w")
    done <<ROOTS_END
$(LC_ALL=C awk -F '|' '{ sub(/\r$/, "") }
  $2 ~ /^[ \t]*[*]*Worktree roots[*]*[ \t]*$/ { v = $3; gsub(/`/, "", v); n = split(v, a, /[,;]/)
    for (i = 1; i <= n; i++) { x = a[i]; sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); y = tolower(x)
      if (x != "" && x != "-" && y != "none" && y != "n/a" && x !~ /^<.*>$/) print x } }' "$r/coordinator/PROJECT.md")
ROOTS_END
  done
  raw+=("${rel[@]}")
  [ ${#raw[@]} -gt 0 ] || return 0
  while IFS= read -r l; do
    l="${l#.}"; case "$l" in ''|.) continue ;; esac   # / or nothing is no project folder
    owns+=("$l")
  done <<OWNS_END
$(canon_all "$sm" "${raw[@]}"; physical "$sm" "${raw[@]}")
OWNS_END
}
is_own() {   # is_own <a session's cwd>: inside one of the project's folders
  local f o
  while IFS= read -r f; do
    f="${f#.}"; [ -n "$f" ] || continue
    for o in "${owns[@]}"; do case "$f/" in "$o/"*) return 0 ;; esac; done
  done <<IS_OWN_END
$(canon_all "$sm" "$1"; physical "$sm" "$1")
IS_OWN_END
  return 1
}
# session_check <what> <address> <id | send>: id - a UUID is a sessionId, anything else a short id;
# send - a name (also without a trailing " [ref]"), an id or a sessionId. Blocks when the sessions it
# names are all outside the project (a name an own session has too passes: it may be meant for that one)
session_check() {
  local what="$1" a="$2" how="$3" k own=0 foreign="" re nm="" ci
  [ -n "$a" ] || return 0
  ci=$(shopt -p nocasematch); shopt -u nocasematch
  re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  [ "$how" = send ] && case "$a" in *' ['*']') nm="${a% \[*}" ;; esac
  read_agents
  k=0
  while [ $k -lt ${#ag_ids[@]} ]; do
    if [ "$how" = send ]; then
      if [ "${ag_names[$k]}" = "$a" ] || [ "${ag_ids[$k]}" = "$a" ] || [ "${ag_sids[$k]}" = "$a" ] ||
        { [ -n "$nm" ] && [ "${ag_names[$k]}" = "$nm" ]; }; then :; else k=$((k + 1)); continue; fi
    elif [[ $a =~ $re ]]; then [ "${ag_sids[$k]}" = "$a" ] || { k=$((k + 1)); continue; }
    else [ "${ag_ids[$k]}" = "$a" ] || { k=$((k + 1)); continue; }; fi
    own_forms
    [ ${#owns[@]} -gt 0 ] || { eval "$ci"; return 0; }   # no project folder known: nothing to tell it by
    if [ -n "${ag_cwds[$k]}" ] && ! is_own "${ag_cwds[$k]}"; then foreign="${ag_cwds[$k]}"; else own=1; fi
    k=$((k + 1))
  done
  eval "$ci"
  [ $own = 0 ] && [ -n "$foreign" ] || return 0
  echo "Blocked by safety-guard: $what a session of another project ($foreign). Ask the owner." >&2
  exit 2
}
# claude stop | rm | respawn | attach <id>..., claude ... --resume <id> (-r <id>, --resume=<id>)
claude_seg() {
  local t verb="" nx=0
  for t in "$@"; do
    if [ $nx = 1 ]; then nx=0; session_check "claude --resume" "$t" id; continue; fi
    case "$t" in
      --resume|-r) nx=1 ;;
      --resume=*) session_check "claude --resume" "${t#--resume=}" id ;;
      -*) ;;
      *) if [ -z "$verb" ]; then
           case "$t" in stop|rm|respawn|attach) verb="$t" ;; *) verb=- ;; esac
         elif [ "$verb" != - ]; then session_check "claude $verb" "$t" id; fi ;;
    esac
  done
}

# --- the owner's working copy: no edit tool under COORD_PROTECTED_ROOT outside its .claude/worktrees/ ---
# Opt-in: unset or empty changes nothing. A relative path counts from the call's cwd; whole path segments
# are compared (<root>-old is another folder), letter case ignored on Windows and macOS only.
if [ -n "${COORD_PROTECTED_ROOT:-}" ]; then
  case "$tool" in
    Edit|Write|MultiEdit|NotebookEdit)
      if command -v jq >/dev/null 2>&1; then
        fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty | strings' 2>/dev/null)
        np=$(printf '%s' "$input" | jq -r '.tool_input.notebook_path // empty | strings' 2>/dev/null)
      fi
      case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*|Darwin) cm="" ;; *) cm=keep ;; esac
      eps=(); efull=()
      for p in "$fp" "$np"; do
        [ -n "$p" ] || continue
        case "$p" in /*|\\*|[A-Za-z]:*) full="$p" ;; *) full="${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}/$p" ;; esac
        eps+=("$p"); efull+=("$full")
      done
      if [ ${#eps[@]} -gt 0 ]; then
        # the root and each path as written and as they lie on disk (links resolved, #121): either form
        # of the path under either form of the root blocks
        # lines: the root and each path as written, then the same as on disk ("." and the form, or empty)
        ef=(); while IFS= read -r l; do ef+=("$l"); done <<EDIT_FORMS_END
$(canon_all "$cm" "$COORD_PROTECTED_ROOT" "${efull[@]}"; physical "$cm" "$COORD_PROTECTED_ROOT" "${efull[@]}")
EDIT_FORMS_END
        ne=$(( ${#efull[@]} + 1 ))
        proots=("${ef[0]}"); [ -n "${ef[$ne]:-}" ] && proots+=("${ef[$ne]#.}")
        k=0
        for p in "${eps[@]}"; do
          k=$((k + 1)); forms=("${ef[$k]}"); [ -n "${ef[$((ne + k))]:-}" ] && forms+=("${ef[$((ne + k))]#.}")
          for full in "${forms[@]}"; do
            for proot in "${proots[@]}"; do
              case "$full/" in
                "$proot/.claude/worktrees/"*) ;;
                "$proot/"?*)
                  echo "Blocked by safety-guard: the owner's working copy is never edited by a worker ($p); work in your worktree. If this is a false positive, ask the owner." >&2
                  exit 2 ;;
              esac
            done
          done
        done
      fi ;;
  esac
fi
# a message to another session (CORE §1.17): its address looked up in the listing
[ "$tool" = SendMessage ] && session_check "a message to" "$to" send
# Line continuations: backslash-newline (bash) and backtick-newline (PowerShell) join the lines.
cmd="${cmd//$cr$nl/$nl}"; cmd="${cmd//\\$nl/}"; cmd="${cmd//\`$nl/ }"
# Comment lines (a "#" at the start of a line) do not count for the project patterns.
lines=$(printf '%s\n' "$cmd" | grep -Ev '^[[:space:]]*#')
[ -z "$lines" ] && exit 0

block() {
  echo "Blocked by safety-guard: $1. If this is a false positive, ask the owner." >&2
  exit 2
}
has() { printf '%s' "$lines" | grep -Eiq -- "$1"; }

# --- split the command into simple commands, one per line, words separated by tabs ---
# Quote-aware: separators (newline ; | & && || ( ) and { } around words) inside quotes do not split,
# quotes are removed.
# $(...) and `...` leave a "$SUBST" marker in the word and become commands of their own; so do the
# inner command of bash -c / pwsh -Command and a heredoc fed to a shell (other heredoc bodies are data).
# An unbalanced quote makes the whole command split again with quotes ignored (stricter, never looser).
SCAN_AWK='
function wrapper(t) { return t ~ /^([{}!]|then|do|else|elif|if|while|until|time|nohup|command|exec|builtin|noglob|xargs)$/ }
# wrappers with options of their own: the options that take a value
function optarg(t) {
  if (t == "sudo") return "^-[ugpcdrt]$"; if (t == "env") return "^-[usc]$"; if (t == "timeout") return "^-[sk]$"
  if (t == "nice") return "^-n$"; if (t == "stdbuf") return "^-[ioe]$"
  # macOS: caffeinate -i, arch -arm64, script -q <file> <command>
  if (t == "caffeinate") return "^-[tw]$"; if (t == "arch") return "^-(arch|e|d)$"; if (t == "script") return "^-[tTc]$"; return ""
}
# the index of the command word: past wrappers (sudo -E, timeout -k 5 30, nice -n 5, stdbuf -oL ...)
# and VAR=value assignments; a wrapper given as a path or with .exe (/usr/bin/env, timeout.exe) counts
function cmdidx(toks, nt,    j, t, ao) {
  j = 1
  while (j <= nt) {
    t = base(toks[j])
    if (t ~ /^g(env|timeout|nice|stdbuf)$/) t = substr(t, 2)   # Homebrew coreutils: gtimeout, gnice ...
    if (wrapper(t) || toks[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { j++; continue }
    ao = optarg(t); if (ao == "") break
    for (j++; j <= nt && toks[j] ~ /^-/; j++) { if (toks[j] == "--") { j++; break }; if (tolower(toks[j]) ~ ao) j++ }
    if ((t == "timeout" || t == "script") && j <= nt) j++   # the duration, or the typescript file of script
  }
  return j
}
# a command word without its folder and .exe: /usr/bin/git, git.exe, C:\x\git.exe -> git
function base(t,    b) { b = tolower(t); sub("^.*[/\\\\]", "", b); sub(/\.exe$/, "", b); return b }
function closep(s, j,    n, dep, c, q, hd, k) {
  n = length(s); dep = 1; q = ""; hd = ""
  for (; j <= n; j++) {
    k = q != "" ? runto(s, j, q, "") : runto(s, j, "\047", "[\"()<\n]"); if (k > 0) { j += k - 1; continue }
    c = substr(s, j, 1)
    if (q != "") { if (c == q) q = ""; continue }
    if (c == "\n" && hd != "") { j = hdend(s, j + 1, hd, HDDASH); hd = ""; continue }
    if (c == "\047" || c == "\"") { q = c; continue }
    if (c == "<" && substr(s, j + 1, 1) == "<" && substr(s, j + 2, 1) != "<") { hd = hdword(s, j + 2); j = HDJ; continue }
    if (c == "(") dep++
    else if (c == ")") { dep--; if (dep == 0) return j }
  }
  return n + 1
}
# the number of ordinary characters from i: up to the string ch or the regex re (a 256-character window)
function runto(s, i, ch, re,    w, k, j) {
  w = substr(s, i, 256); k = length(w)
  if (re != "" && match(w, re)) k = RSTART - 1
  if (ch != "") { j = index(w, ch); if (j && j - 1 < k) k = j - 1 }
  return k
}
function closet(s, j,    n, c) {
  n = length(s)
  while (j <= n) {
    j += runto(s, j, "`", ""); if (j > n) break
    c = substr(s, j, 1)
    if (c == "`" && substr(s, j - 1, 1) != "\\") return j
    if (c == "`") j++
  }
  return n + 1
}
# heredoc word after "<<": sets HDJ (its last index) and HDDASH; returns the delimiter
function hdword(s, j,    n, c, w) {
  n = length(s); HDDASH = 0; w = ""
  if (substr(s, j, 1) == "-") { HDDASH = 1; j++ }
  while (j <= n && (substr(s, j, 1) == " " || substr(s, j, 1) == "\t")) j++
  for (; j <= n; j++) { c = substr(s, j, 1); if (c ~ /[ \t\r\n;|&()<>]/) break; if (c != "\047" && c != "\"" && c != "\\") w = w c }
  HDJ = j - 1; return w
}
# heredoc body from j up to the delimiter line: sets HDBODY; returns the index of that line s newline
function hdend(s, j, delim, dash,    n, k, line, st) {
  n = length(s); st = j
  while (j <= n) {
    k = index(substr(s, j), "\n"); if (k == 0) k = n - j + 2
    line = substr(s, j, k - 1); if (dash) sub(/^\t+/, "", line); sub(/\r$/, "", line)
    if (line == delim) { HDBODY = substr(s, st, j - st); return j + k - 1 }
    j += k
  }
  HDBODY = substr(s, st); return n
}
function isshell(toks, nt,    j) {
  j = cmdidx(toks, nt)
  SHJ = j
  return j <= nt && base(toks[j]) ~ /^(bash|sh|zsh|dash|ksh|pwsh|powershell)$/
}
function seg(toks, nt, depth, qm, pp,    j, t, line, k, m, inner, lt) {
  if (nt == 0) return
  line = ""
  for (j = 1; j <= nt; j++) { t = toks[j]; gsub(/[\t\r\n]/, " ", t); line = line ((j > 1) ? "\t" : "") t }
  OUT = OUT (pp ? "\001|\t" : "") line "\n"   # a first word \001| : this command reads the previous one through |
  if (!isshell(toks, nt)) return
  j = SHJ
  for (k = j + 1; k <= nt; k++) { lt = tolower(toks[k]); if (lt ~ /^-[a-z]*c$/ || lt ~ /^-com(m(a(n(d)?)?)?)?$/) break }
  if (k < nt && toks[k + 1] == "--") k++
  if (k >= nt) return
  inner = toks[k + 1]; for (m = k + 2; m <= nt; m++) inner = inner " " toks[m]
  scan(inner, depth + 1, qm)
}
function scan(s, depth, qm,    n, i, c, d, p, q, tok, st, toks, nt, k, hd, hdd, hdsh, body, bd, pp, e) {
  if (depth > 8) return
  n = length(s); q = ""; tok = ""; st = 0; nt = 0; hd = ""; bd = 0; pp = 0
  for (i = 1; i <= n; i++) {
    k = (q == "\047") ? runto(s, i, "\047", "") : (q == "\"") ? runto(s, i, "", "[\"\\\\$`]") : runto(s, i, "\047", "[ \t\r\n;|&()<>{}\"\\\\$`#]")
    if (k > 0) { tok = tok substr(s, i, k); i += k - 1; continue }
    c = substr(s, i, 1); d = substr(s, i + 1, 1); p = (i > 1) ? substr(s, i - 1, 1) : ""
    if (q == "\047") { if (c == "\047") q = ""; else tok = tok c; continue }
    if (q == "\"") {
      if (c == "\\" && (d == "\"" || d == "\\" || d == "$" || d == "`")) { tok = tok d; i++; continue }
      if (c == "\"") { q = ""; continue }
      if (c == "$" && d == "(") { k = closep(s, i + 2); scan(substr(s, i + 2, k - i - 2), depth + 1, qm); tok = tok "$SUBST"; i = k; continue }
      if (c == "`") { k = closet(s, i + 1); scan(substr(s, i + 1, k - i - 1), depth + 1, qm); tok = tok "$SUBST"; i = k; continue }
      tok = tok c; continue
    }
    if (qm && c == "\\" && (d == "\"" || d == "\047" || d == "\\")) { tok = tok d; st = 1; i++; continue }
    if (c == "\047" || c == "\"") { if (qm) { q = c; st = 1 }; continue }
    if (c == "$" && d == "(") { k = closep(s, i + 2); scan(substr(s, i + 2, k - i - 2), depth + 1, qm); tok = tok "$SUBST"; st = 1; i = k; continue }
    if (c == "`") { k = closet(s, i + 1); scan(substr(s, i + 1, k - i - 1), depth + 1, qm); tok = tok "$SUBST"; st = 1; i = k; continue }
    if (c == " " || c == "\t" || c == "\r") { if (tok != "") toks[++nt] = tok; tok = ""; st = 0; bd = 0; continue }
    if (c == "#" && tok == "" && !st) { while (i < n && substr(s, i + 1, 1) != "\n") i++; continue }
    if (c == "<" && d == "<" && substr(s, i + 2, 1) != "<") {
      if (tok != "") toks[++nt] = tok; tok = ""; st = 0; bd = 0
      hdsh = isshell(toks, nt); hd = hdword(s, i + 2); hdd = HDDASH; i = HDJ; continue
    }
    if (c == ">" || c == "<") {
      if (tok != "" && tok !~ /^[0-9]+$/ && tok != "&" && tok != "*" && tok !~ /[<>]$/) { toks[++nt] = tok; tok = ""; bd = 0 }
      tok = tok c; st = 1; continue
    }
    if (c == "&" && (p == ">" || p == "<" || d == ">")) { tok = tok c; st = 1; continue }
    # { and } around words are groups and script blocks (& {git push}, % { ... }); inside a word they
    # are data (${HOME}, @{0}, refs/heads/main^{})
    if (c == "{" && tok != "") { bd++; tok = tok c; continue }
    if (c == "}" && bd > 0) { bd--; tok = tok c; continue }
    if (c == "\n" || c == ";" || c == "|" || c == "&" || c == "(" || c == ")" || c == "{" || c == "}") {
      if (tok != "") toks[++nt] = tok; tok = ""; st = 0; bd = 0; e = (nt == 0)
      seg(toks, nt, depth, qm, pp); nt = 0
      pp = (c == "|" && d != "|" && p != "|") || (e && pp)
      if (c == "\n" && hd != "") { k = hdend(s, i + 1, hd, hdd); body = HDBODY; hd = ""; if (hdsh) scan(body, depth + 1, 0); i = k }
      continue
    }
    tok = tok c
  }
  if (q != "") FAIL = 1
  if (tok != "") toks[++nt] = tok
  seg(toks, nt, depth, qm, pp)
}
{ all = (NR > 1) ? all "\n" $0 : $0 }
END {
  OUT = ""; FAIL = 0; scan(all, 0, 1)
  if (FAIL) { OUT = ""; scan(all, 0, 0) }
  printf "%s", OUT
}'
segments=$(printf '%s' "$cmd" | awk "$SCAN_AWK")

# --- helpers (case-insensitive matching: GIT PUSH ORIGIN MAIN counts) ---
shopt -s nocasematch
RE_ASSIGN='^[A-Za-z_][A-Za-z0-9_]*='
RE_REDIR='^[0-9*]*&?[<>]'
RE_REDIR_OP='^[0-9*]*&?[<>]+[&|]?$'
RE_RMREC='^-[rRfFvViIdDpP]*[rR][rRfFvViIdDpP]*$'
RE_PSREC='^-[rR]([eE]([cC]([uU]([rR]([sS][eE]?)?)?)?)?)?(:\$?[tT][rR][uU][eE])?$'
RE_WT='(^|[/\\])\.claude([/\\]worktrees([/\\][^/\\]+)?)?$'   # a worktree, the worktrees' folder, .claude
RE_TILDE='^~[^/\\]+$'   # ~name: a user's home (bash only: PowerShell takes ~tmp for a folder's name)

dir="${cwd:-${CLAUDE_PROJECT_DIR:-.}}"   # where the next command runs (follows cd / Set-Location)
ov_dir=""; ov_branch=""                  # a checkout / switch earlier in this command: dir and branch

# one of the protected branches (prot, above): the whole name, literally, letter case ignored
is_protected() { local b; for b in "${prot[@]}"; do case "$1" in "$b") return 0 ;; esac; done; return 1; }
# A path relative to a base; "?" when it cannot be known (variables). . and ./ are the base itself.
compose() {
  local p="$2"
  while :; do case "$p" in ./*|.\\*) p="${p#??}" ;; *) break ;; esac; done
  [ "$p" = . ] && p=""
  case "$p" in
    '') printf '%s' "$1" ;;
    *'$'*|*'%'*) printf '?' ;;
    '~'|'~/'*|'~\'*) printf '%s%s' "$HOME" "${p#?}" ;;
    /*|\\*|[A-Za-z]:*) printf '%s' "$p" ;;
    *) if [ "$1" = "?" ]; then printf '?'; else printf '%s/%s' "$1" "$p"; fi ;;
  esac
}
# canon_all, physical: above, with the edit-tool check
branch_in() {
  if [ "$1" = "$ov_dir" ]; then printf '%s' "$ov_branch"; return; fi
  [ "$1" = "?" ] && return
  git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null
}
# refs/heads/main^{} , heads/main , main~0 , HEAD@{0} -> the branch name
norm_ref() {
  local x
  x=$(printf '%s' "$1" | sed -E 's/(\^\{[^}]*\}|[~^][0-9]*|@\{[^}]*\})+$//')
  case "$x" in refs/heads/*) x="${x:11}" ;; heads/*) x="${x:6}" ;; esac
  printf '%s' "$x"
}
is_current() { case "$1" in ''|HEAD|@|*'$'*) return 0 ;; esac; return 1; }

# --- git push: protected targets, every-branch pushes, pushes resolving to a protected current branch ---
# Work branches may be pushed, force-pushed (e.g. after a rebase) and deleted freely.
push_seg() {
  local d="$1" remote=0 refs=0 cur=0 tags=0 skip=0 t r dst br
  shift
  for t in "$@"; do
    if [ $skip = 1 ]; then skip=0; continue; fi
    case "$t" in
      --mirror) block "mirror push (overwrites every branch, incl. protected ones)" ;;
      --all|--branches) block "push of every branch (incl. protected ones)" ;;
      --tags) tags=1; continue ;;
      --repo=*) remote=1; continue ;;
      --repo) remote=1; skip=1; continue ;;
      -o|--push-option|--receive-pack|--exec) skip=1; continue ;;
      -*) continue ;;
    esac
    if [ $remote = 0 ]; then remote=1; continue; fi
    refs=$((refs + 1))
    r="${t#+}"
    case "$r" in ''|:) block "push of all matching branches (incl. protected ones)" ;; esac
    case "$r" in *:*) dst="${r#*:}"; [ -z "$dst" ] && dst="${r%%:*}" ;; *) dst="$r" ;; esac
    dst=$(norm_ref "$dst")
    is_protected "$dst" && block "push to a protected branch ($dst)"
    is_current "$dst" && cur=1
  done
  [ $refs = 0 ] && [ $tags = 1 ] && return   # tags only: not a branch push
  if [ $refs = 0 ] || [ $cur = 1 ]; then
    br=$(branch_in "$d")
    is_protected "$br" && block "push while on $br"
  fi
}
# --- deleting a protected branch (any delete flag, the name anywhere in the arguments) ---
branch_seg() {
  local del=0 t; local names=()
  for t in "$@"; do
    case "$t" in --delete) del=1 ;; --*) ;; -*d*) del=1 ;; -*) ;; *) names+=("$t") ;; esac
  done
  [ $del = 1 ] || return
  for t in "${names[@]}"; do t="$(norm_ref "$t")"; is_protected "$t" && block "deleting a protected branch ($t)"; done
}
updref_seg() {
  local del=0 t; local names=()
  for t in "$@"; do case "$t" in -d|--delete) del=1 ;; -*) ;; *) names+=("$t") ;; esac; done
  [ $del = 1 ] || return
  for t in "${names[@]}"; do t="$(norm_ref "$t")"; is_protected "$t" && block "deleting a protected branch ($t)"; done
}
# git checkout / switch: a later bare push in the same directory pushes that branch.
checkout_seg() {
  local d="$1" t newb="" first="" nx=0 track=0 nargs=0 prev
  shift
  for t in "$@"; do
    if [ $nx = 1 ]; then newb="$t"; nx=0; continue; fi
    case "$t" in
      --) return ;;
      -b|-c|--create|--force-create|--orphan) nx=1 ;;
      --detach) newb="(detached)" ;;
      -t|--track|--track=*) track=1 ;;
      -) nargs=$((nargs + 1)); [ -z "$first" ] && first="-" ;;
      -*) ;;
      *) nargs=$((nargs + 1)); [ -z "$first" ] && first="$t" ;;
    esac
  done
  if [ -n "$newb" ]; then ov_dir="$d"; ov_branch="$newb"; return; fi
  [ -n "$first" ] || return
  [ $nargs -gt 1 ] && return   # git checkout <branch> <file>: restores a file, the branch stays
  # git checkout - : the previous branch (after a checkout earlier in this command: the current one)
  if [ "$first" = "-" ]; then
    [ "$d" = "?" ] && return
    if [ "$d" = "$ov_dir" ]; then prev=$(git -C "$d" symbolic-ref --short -q HEAD 2>/dev/null)
    else prev=$(git -C "$d" rev-parse --abbrev-ref '@{-1}' 2>/dev/null); fi
    [ -n "$prev" ] && { ov_dir="$d"; ov_branch="$prev"; }
    return
  fi
  # --track origin/main creates and checks out main
  if [ $track = 1 ]; then case "$first" in */*) ov_dir="$d"; ov_branch="${first#*/}"; return ;; esac; fi
  if is_protected "$(norm_ref "$first")" || { [ "$d" != "?" ] && git -C "$d" show-ref -q --verify "refs/heads/$first" 2>/dev/null; }; then
    ov_dir="$d"; ov_branch="$first"
  fi
}
git_seg() {
  local eff="$dir" sub
  while [ $# -gt 0 ]; do
    if [ "$1" = "-C" ]; then eff=$(compose "$eff" "${2:-}"); [ $# -ge 2 ] && shift; shift; continue; fi
    case "$1" in
      -c|--git-dir|--work-tree|--namespace|--config-env|--super-prefix) [ $# -ge 2 ] && shift; shift ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || return
  sub="$1"; shift
  case "$sub" in
    push) push_seg "$eff" "$@" ;;
    branch) branch_seg "$@" ;;
    update-ref) updref_seg "$@" ;;
    checkout|switch) checkout_seg "$eff" "$@" ;;
    worktree) worktree_seg "$@" ;;
  esac
}
# git worktree remove --force throws away what the worktree holds: the cleanup script checks first
worktree_seg() {
  local t
  [[ ${1:-} == remove ]] || return
  shift
  for t in "$@"; do case "$t" in --force|-f|-ff) block "removing a worktree by force (use the cleanup script)" ;; esac; done
}
cd_seg() {
  local t x=""
  for t in "$@"; do case "$t" in -*) ;; *) x="$t"; break ;; esac; done
  [ -z "$x" ] && x='~'
  [ "$x" = "-" ] && { dir="?"; return; }
  dir=$(compose "$dir" "$x")
}
# --- irreversible removals: / , a drive, home, or a worktree by hand ---
strip_all() {   # x/* , x/** , x/. and trailing separators -> x
  local x="$1"
  while :; do case "$x" in */\*\*|*\\\*\*) x="${x%?}" ;; */\*|*\\\*|*/.|*\\.) x="${x%??}" ;; */|*\\) x="${x%?}" ;; *) break ;; esac; done
  printf '%s' "$x"
}
# home and the project's folders (CLAUDE_PROJECT_DIR, the top of the repository the session works in and
# that repository's main checkout, from a worktree), each in canon form as written and as it lies on disk
# (links resolved); read once, on the first removal
homes=(); roots=(); forms_read=0
protected_forms() {
  local c out common h l k=0 nh; local raw=()
  [ $forms_read = 1 ] && return; forms_read=1
  for h in "$HOME" "${USERPROFILE:-}"; do [ -n "$h" ] && raw+=("$h"); done
  nh=${#raw[@]}
  [ -n "${CLAUDE_PROJECT_DIR:-}" ] && raw+=("$CLAUDE_PROJECT_DIR")
  c="${cwd:-${CLAUDE_PROJECT_DIR:-}}"
  if [ -n "$c" ] && out=$(git -C "$c" rev-parse --path-format=absolute --show-toplevel --git-common-dir 2>/dev/null); then
    raw+=("${out%%$nl*}")
    common="${out#*$nl}"
    case "$common" in */.git) raw+=("${common%/.git}") ;; esac
  fi
  [ ${#raw[@]} -gt 0 ] || return 0
  # as written (one line per path), then as on disk ("." and the form, or an empty line)
  while IFS= read -r l; do
    k=$((k + 1))
    if [ $k -gt ${#raw[@]} ]; then [ -n "$l" ] || continue; l="${l#.}"; fi
    if [ $(( (k - 1) % ${#raw[@]} )) -lt $nh ]; then homes+=("$l"); else roots+=("$l"); fi
  done <<FORMS_END
$(canon_all "" "${raw[@]}"; physical "" "${raw[@]}")
FORMS_END
}
rm_target() {   # rm_target <path> <1: the project's folder and the folders holding it count too>
  local x full fr ph f h r; local forms=()
  x=$(strip_all "$1")
  [[ $x =~ $RE_WT ]] && block "removing a worktree by hand (use the cleanup script)"
  case "$x" in
    ''|'~'|'$HOME'|'${HOME}'|'$env:USERPROFILE'|'${env:USERPROFILE}'|'$env:HOME'|'$env:HOMEDRIVE'|'$env:SystemDrive'|'%USERPROFILE%'|'%HOMEDRIVE%'|'%SystemDrive%'|[A-Za-z]:)
      block "recursive removal of /, a drive or home" ;;
  esac
  # ~name: a user's home (~ followed by a name, nothing after it but /, /* or /**) - in bash; the
  # PowerShell tool does not expand it (Remove-Item ~tmp is a folder named ~tmp)
  [ "$tool" != PowerShell ] && [[ $x =~ $RE_TILDE ]] && block "recursive removal of /, a drive or home"
  # the full path: relative targets (., *, .., x) from the directory a cd led to; home given literally
  # (/c/Users/x, C:\Users\x), a drive as /c, /mnt/c or /cygdrive/c; . and x/.. taken out
  fr=$(compose "$dir" "$1")
  [ "$fr" = "?" ] && return
  fr=$(strip_all "$fr")
  # as written and as it lies on disk (a link to the project, home or a worktree, #121)
  full=$(canon_all "" "$fr"; physical "" "$fr")
  ph="${full#*$nl}"; [ "$ph" = "$full" ] && ph=""; full="${full%%$nl*}"
  case "$full" in ''|[a-z]:) block "recursive removal of /, a drive or home" ;; esac
  # . or * inside a worktree (after a cd to it, or with it as the working folder), .. up to one
  [[ $full =~ $RE_WT ]] && block "removing a worktree by hand (use the cleanup script)"
  # the same checks on the path as it lies on disk
  forms=("$full")
  [ -n "$ph" ] && forms+=("${ph#.}")
  protected_forms
  for f in "${forms[@]}"; do
    case "$f" in ''|[a-z]:) block "recursive removal of /, a drive or home" ;; esac
    [[ $f =~ $RE_WT ]] && block "removing a worktree by hand (use the cleanup script)"
    # home or a folder that holds it
    for h in "${homes[@]}"; do case "$h/" in "$f/"*) block "recursive removal of /, a drive or home" ;; esac; done
  done
  [ "${2:-1}" = 1 ] || return 0
  # the project's folder or a folder that holds it
  for f in "${forms[@]}"; do
    for r in "${roots[@]}"; do
      case "$r/" in "$f/"*) block "recursive removal of the project or a folder that holds it" ;; esac
    done
  done
}
rm_seg() {
  local b="$1" rec=0 dd=0 t; local tg=()
  shift
  for t in "$@"; do
    if [ $dd = 1 ]; then tg+=("$t"); continue; fi
    case "$t" in
      --) dd=1; continue ;;
      --recursive) rec=1; continue ;;
      --*) continue ;;
      /s) case "$b" in rd|rmdir|del|erase) rec=1; continue ;; esac ;;
      /q|/f) case "$b" in rd|rmdir|del|erase) continue ;; esac ;;
      -*) if [[ $t =~ $RE_RMREC ]] || [[ $t =~ $RE_PSREC ]]; then rec=1; fi; continue ;;
    esac
    tg+=("$t")
  done
  [ $rec = 1 ] || return
  # Get-ChildItem C:\ | Remove-Item -Recurse : the paths come through the pipe
  [ ${#tg[@]} = 0 ] && [ $piped = 1 ] && tg=("${prev_tg[@]}")
  for t in "${tg[@]}"; do rm_target "$t" 1; done
}
# the paths a listing (Get-ChildItem, ls, dir) hands on through a pipe; none: the current directory
list_seg() {
  local t
  for t in "$@"; do case "$t" in -*) ;; *) cur_tg+=("$t") ;; esac; done
  [ ${#cur_tg[@]} -gt 0 ] || cur_tg=(.)
}
# find <path> -delete: the paths before the first expression; with a test (-name ...) it deletes what
# matches, so the project's folder may be its path
find_seg() {
  local t del=0 on=1 all=1; local tg=()
  for t in "$@"; do
    case "$t" in -delete) del=1 ;; -depth) on=0 ;; -*|"!") on=0; all=0 ;; *) if [ $on = 1 ]; then tg+=("$t"); else all=0; fi ;; esac
  done
  [ $del = 1 ] || return
  for t in "${tg[@]}"; do rm_target "$t" $all; done
}

PIPE=$'\001|'; cur_tg=()
while IFS="$tab" read -r -a T; do
  prev_tg=("${cur_tg[@]}"); cur_tg=()
  piped=0
  if [ "${T[0]:-}" = "$PIPE" ]; then piped=1; T=("${T[@]:1}"); fi
  # redirections (2>&1, > out.txt) are not arguments
  A=(); skip=0
  for t in "${T[@]}"; do
    if [ $skip = 1 ]; then skip=0; continue; fi
    if [[ $t =~ $RE_REDIR ]]; then [[ $t =~ $RE_REDIR_OP ]] && skip=1; continue; fi
    A+=("$t")
  done
  # the command word: after wrappers ({ ( ! then do sudo env ...), their options (sudo -E,
  # timeout -k 5 30, nice -n 5, stdbuf -oL ...) and VAR=value assignments; a wrapper given as a path
  # or with .exe (/usr/bin/env, timeout.exe) counts
  i=0; n=${#A[@]}
  while [ $i -lt $n ]; do
    t="${A[$i]}"; [[ $t =~ $RE_ASSIGN ]] && { i=$((i + 1)); continue; }
    t="${t##*/}"; t="${t##*\\}"; case "$t" in *.exe) t="${t%????}" ;; esac
    case "$t" in
      '{'|'}'|'!'|then|do|else|elif|if|while|until|time|nohup|command|exec|builtin|noglob|xargs) i=$((i + 1)); continue ;;
      sudo) ao='^-[ugpcdrt]$' ;;
      env|genv) ao='^-[usc]$' ;;
      timeout|gtimeout) ao='^-[sk]$' ;;
      nice|gnice) ao='^-n$' ;;
      stdbuf|gstdbuf) ao='^-[ioe]$' ;;
      caffeinate) ao='^-[tw]$' ;;            # macOS: caffeinate -i, arch -arm64, script -q <file> <command>
      arch) ao='^-(arch|e|d)$' ;;
      script) ao='^-[tTc]$' ;;
      *) break ;;
    esac
    i=$((i + 1))
    while [ $i -lt $n ]; do
      case "${A[$i]}" in --) i=$((i + 1)); break ;; -*) ;; *) break ;; esac
      [[ ${A[$i]} =~ $ao ]] && i=$((i + 1))
      i=$((i + 1))
    done
    case "$t" in timeout|gtimeout|script) [ $i -lt $n ] && i=$((i + 1)) ;; esac   # the duration, or the typescript file of script
  done
  [ $i -lt $n ] || continue
  w="${A[$i]}"; w="${w##*/}"; w="${w##*\\}"; case "$w" in *.exe) w="${w%????}" ;; esac
  case "$w" in
    git) git_seg "${A[@]:$((i + 1))}" ;;
    cd|pushd|chdir|set-location|sl|push-location) cd_seg "${A[@]:$((i + 1))}" ;;
    rm|remove-item|ri|del|erase|rd|rmdir) rm_seg "$w" "${A[@]:$((i + 1))}" ;;
    find) find_seg "${A[@]:$((i + 1))}" ;;
    get-childitem|gci|ls|dir|get-item|gi) list_seg "${A[@]:$((i + 1))}" ;;
    claude) claude_seg "${A[@]:$((i + 1))}" ;;
  esac
done <<SAFETY_GUARD_SEGMENTS_END
$segments
SAFETY_GUARD_SEGMENTS_END
shopt -u nocasematch

# --- project-specific patterns: one per line, trimmed; blank lines and # comments skipped ---
deny_file="${CLAUDE_PROJECT_DIR:-.}/.claude/coordinator-deny.txt"
# a deny file that is there but cannot be read (no read permission, a folder) blocks every call; it
# is opened to find out ([ -r ] says yes in Git Bash when an NTFS permission denies the read)
if [ -e "$deny_file" ] && { [ ! -f "$deny_file" ] || ! { : < "$deny_file"; } 2>/dev/null; }; then
  block "project rule file cannot be read: .claude/coordinator-deny.txt"
fi
if [ -f "$deny_file" ]; then
  # UTF-16 (what Windows PowerShell 5.1's > writes: a FF FE or FE FF BOM, NUL bytes) is not read as
  # nothing: it blocks every call until it is saved as UTF-8 (read -d '' finds a NUL byte)
  IFS= read -r pattern < "$deny_file"
  if IFS= read -r -d '' _ < "$deny_file"; then utf16=1; else case "$pattern" in $'\377\376'*|$'\376\377'*) utf16=1 ;; *) utf16=0 ;; esac; fi
  [ $utf16 = 1 ] && block "project rule file cannot be read: .claude/coordinator-deny.txt (not UTF-8: re-save it as UTF-8)"
  bom=$'\357\273\277'; first=1
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    [ $first = 1 ] && pattern="${pattern#"$bom"}"; first=0   # a file saved with a UTF-8 BOM
    pattern="${pattern%$cr}"   # a file saved with CRLF
    pattern="${pattern#"${pattern%%[![:space:]]*}"}"; pattern="${pattern%"${pattern##*[![:space:]]}"}"
    case "$pattern" in ''|'#'*) continue ;; esac
    has "$pattern"; rc=$?
    [ $rc = 0 ] && block "project rule: $pattern"
    [ $rc = 1 ] || block "project rule cannot be read: $pattern"
  done < "$deny_file"
fi

exit 0

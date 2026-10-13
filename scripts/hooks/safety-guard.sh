#!/usr/bin/env bash
# PreToolUse safety hook for coordinator projects (Bash / PowerShell tools).
# Reads the tool call JSON on stdin; exit 2 blocks the call and shows the reason to Claude.
# A safety net only — the real enforcement is branch protection on the code host (CORE §2); deliberate
# obfuscation (eval, quoting tricks, aliases ...) is out of scope (TOOLKIT.md *Safety*).
# Extra project patterns (one extended regex per line, '#' comments; a pattern that cannot be read
# blocks every call): .claude/coordinator-deny.txt
# Self-test: scripts/hooks/safety-guard.sh --self-test   (prints to stdout so the session sees it)
# Works on macOS (bash 3.2, BSD awk / sed), Linux and Windows (Git Bash); jq is used when present.
# Same rules as safety-guard.ps1, both checked against tests/safety-guard/cases.txt.

if [ "${1:-}" = "--self-test" ]; then
  # a push to main must block (exit 2) and a work-branch push must pass (exit 0): a guard that blocks
  # everything (a syntax error also exits 2) is not working either
  out=$(printf '%s' '{"tool_input":{"command":"git push --force origin main"}}' | bash "$0" 2>/dev/null; echo $?)
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
function emit(all,    m, P, i, p, c, r, v, h, k) {
  m = split(all, P, "\\"); printf "%s", P[1]
  for (i = 2; i <= m; i++) {
    p = P[i]
    if (p == "") { printf "\\"; i++; if (i <= m) printf "%s", P[i]; continue }
    c = substr(p, 1, 1); r = substr(p, 2)
    if (c == "n") c = "\n"; else if (c == "t") c = "\t"; else if (c == "r") c = "\r"; else if (c == "b" || c == "f") c = " "
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
    return 1
  }
  if (match(substr(s, i, 64), /^(-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?|true|false|null)/)) { i += RLENGTH; return 1 }
  return 0
}
{ all = (NR > 1) ? all "\n" $0 : $0 }
END {
  s = all; n = length(s); i = 1; CMD = ""; CWD = ""
  ws(); if (substr(s, i, 1) != "{" || !val("")) exit 3
  ws(); if (i <= n) exit 3
  emit(CWD); printf "\n"; emit(CMD); printf "."
}'
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$input" | jq -e 'type == "object"' >/dev/null 2>&1 || unreadable
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
else
  both=$(printf '%s' "$input" | awk "$JSON_AWK") || unreadable
  both="${both%.}"; cwd="${both%%$nl*}"; cmd="${both#*$nl}"
fi
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
# and VAR=value assignments
function cmdidx(toks, nt,    j, t, ao) {
  j = 1
  while (j <= nt) {
    t = tolower(toks[j])
    if (t ~ /^g(env|timeout|nice|stdbuf)$/) t = substr(t, 2)   # Homebrew coreutils: gtimeout, gnice ...
    if (wrapper(t) || toks[j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { j++; continue }
    ao = optarg(t); if (ao == "") break
    for (j++; j <= nt && toks[j] ~ /^-/; j++) { if (toks[j] == "--") { j++; break }; if (tolower(toks[j]) ~ ao) j++ }
    if ((t == "timeout" || t == "script") && j <= nt) j++   # the duration, or the typescript file of script
  }
  return j
}
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
RE_WT='(^|[/\\])\.claude[/\\]worktrees([/\\][^/\\]+)?$'
RE_TILDE='^~[^/\\]+$'   # ~name: a user's home

dir="${cwd:-${CLAUDE_PROJECT_DIR:-.}}"   # where the next command runs (follows cd / Set-Location)
ov_dir=""; ov_branch=""                  # a checkout / switch earlier in this command: dir and branch

is_protected() { case "$1" in main|master) return 0 ;; esac; return 1; }
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
# A path in one form for comparing: / separators, none repeated or trailing, lower case, a drive as
# c: (C:\x, /c/x, /mnt/c/x and /cygdrive/c/x are all c:/x); / itself is empty.
canon() {
  printf '%s' "$1" | tr '\\A-Z' '/a-z' |
    sed -E -e 's#//+#/#g' -e 's#/+$##' -e 's#^/(mnt/|cygdrive/)?([a-z])$#\2:#' -e 's#^/(mnt/|cygdrive/)?([a-z])/#\2:/#'
}
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
    is_protected "$dst" && block "push to a protected branch"
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
  for t in "${names[@]}"; do is_protected "$(norm_ref "$t")" && block "deleting a protected branch"; done
}
updref_seg() {
  local del=0 t; local names=()
  for t in "$@"; do case "$t" in -d|--delete) del=1 ;; -*) ;; *) names+=("$t") ;; esac; done
  [ $del = 1 ] || return
  for t in "${names[@]}"; do is_protected "$(norm_ref "$t")" && block "deleting a protected branch"; done
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
rm_target() {
  local x full h
  x=$(strip_all "$1")
  [[ $x =~ $RE_WT ]] && block "removing a worktree by hand (use the cleanup script)"
  case "$x" in
    ''|'~'|'$HOME'|'${HOME}'|'$env:USERPROFILE'|'${env:USERPROFILE}'|'$env:HOME'|'$env:HOMEDRIVE'|'$env:SystemDrive'|'%USERPROFILE%'|'%HOMEDRIVE%'|'%SystemDrive%'|[A-Za-z]:)
      block "recursive removal of /, a drive or home" ;;
  esac
  # ~name: a user's home (~ followed by a name, nothing after it but /, /* or /**)
  [[ $x =~ $RE_TILDE ]] && block "recursive removal of /, a drive or home"
  # the full path: relative targets (., *, x) from the directory a cd led to; home given literally
  # (/c/Users/x, C:\Users\x), a drive as /c, /mnt/c or /cygdrive/c
  full=$(compose "$dir" "$1")
  [ "$full" = "?" ] && return
  full=$(canon "$(strip_all "$full")")
  case "$full" in ''|[a-z]:) block "recursive removal of /, a drive or home" ;; esac
  # . or * inside a worktree (after a cd to it, or with it as the working folder)
  [[ $full =~ $RE_WT ]] && block "removing a worktree by hand (use the cleanup script)"
  for h in "$HOME" "${USERPROFILE:-}"; do
    [ -n "$h" ] && [ "$full" = "$(canon "$h")" ] && block "recursive removal of /, a drive or home"
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
  for t in "${tg[@]}"; do rm_target "$t"; done
}
# the paths a listing (Get-ChildItem, ls, dir) hands on through a pipe; none: the current directory
list_seg() {
  local t
  for t in "$@"; do case "$t" in -*) ;; *) cur_tg+=("$t") ;; esac; done
  [ ${#cur_tg[@]} -gt 0 ] || cur_tg=(.)
}
# find <path> -delete: the paths before the first expression
find_seg() {
  local t del=0 on=1; local tg=()
  for t in "$@"; do
    case "$t" in -delete) del=1 ;; -*|"!") on=0 ;; *) [ $on = 1 ] && tg+=("$t") ;; esac
  done
  [ $del = 1 ] || return
  for t in "${tg[@]}"; do rm_target "$t"; done
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
  # timeout -k 5 30, nice -n 5, stdbuf -oL ...) and VAR=value assignments
  i=0; n=${#A[@]}
  while [ $i -lt $n ]; do
    t="${A[$i]}"
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
      *) if [[ $t =~ $RE_ASSIGN ]]; then i=$((i + 1)); continue; fi; break ;;
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
  esac
done <<SAFETY_GUARD_SEGMENTS_END
$segments
SAFETY_GUARD_SEGMENTS_END
shopt -u nocasematch

# --- project-specific patterns: one per line, trimmed; blank lines and # comments skipped ---
deny_file="${CLAUDE_PROJECT_DIR:-.}/.claude/coordinator-deny.txt"
# a deny file that is there but cannot be read (no read permission, a folder) blocks every call
if [ -e "$deny_file" ] && { [ ! -f "$deny_file" ] || [ ! -r "$deny_file" ]; }; then
  block "project rule file cannot be read: .claude/coordinator-deny.txt"
fi
if [ -f "$deny_file" ]; then
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

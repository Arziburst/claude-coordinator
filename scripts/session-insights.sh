#!/usr/bin/env bash
# Where a Claude Code session lost money, time, quality or stability (macOS / Linux, no dependencies;
# Windows: session-insights.ps1). The input of the weekly retro (CORE §7a); reads only, sends nothing.
#   scripts/session-insights.sh <session-id | id prefix | a subagent's agentId | transcript.jsonl> [--detail]
#   scripts/session-insights.sh --since <UTC time 2026-10-05T17:00:00Z, or Unix seconds> [--detail]
#                               [--until <UTC time>] [--skip-tests] [--project <folder>]
#                               every transcript on the account from then on (each record by its timestamp;
#                               --until: before that time). The retro's filters, by a session's name (its last
#                               customTitle / agentName) and its first cwd, a subagent's by its parent's:
#                               --skip-tests leaves out probe and self-test sessions - a name with probe,
#                               selftest or self-test as a word before its first colon (#0 probe: ..., probe:
#                               ..., selftest), a task #st<n> (#st1 lead: selftest), or a cwd inside a
#                               coordinator-selftest folder; a product task about a self-test stays (its
#                               title, after the colon, only names it); --project keeps the sessions whose
#                               first cwd is the folder or inside it (\ read as /, case ignored, C:/x as /c/x)
# One session is its transcript and its subagents'; each transcript is read in order on its own. Lines,
# tab-separated, one kind per line, no header (nothing at all for a session without messages):
#   block  <reason>  count=<n> changed=<n> retried=<n> around=<n> stopped=<n>   — per safety-guard reason
#          (the text after "Blocked by safety-guard: " up to ". If this is a false positive"; a path in
#          parentheses shown as (<path>)) and "deny rule" (a "Permission to use ... has been denied"
#          result). The transcript's next tool call after the block: retried = the same tool with the same
#          command (else file_path, else input); around = another call naming one of the blocked call's
#          targets (its file_path; in its command the words main / master and the words holding a / or \
#          with 2 letters or digits, /dev/... aside; "push while on <b>": b) as a whole word, case and
#          \ against / ignored — a signal, not proof; stopped = an end_turn or the transcript's end first;
#          changed = anything else
#   refusal  <source>  count=<n> changed=<n> retried=<n> around=<n> stopped=<n>   — the other refusals, read
#          as blocks: "hook <script>" (another hook's error, its script's name without folders; "hook" when
#          its command is not shown), "classifier" (auto mode), "safety check" (built in), "user" (the
#          user's no), "other" (any other rejected permission)
#   tool_error  <tool>  count=<n> repeated=<n> exit_only=<n>   — results with is_error true that are no
#          block, refusal or interrupt; repeated = the tool's next call had the same command (else the same
#          input) and failed again; exit_only = errors whose whole text is "Exit code <n>" (grep without a
#          match, a diff that differs): left out of count, which means failures shown
#   waiting  minutes=<m> calls=<n>   — calls over 2 minutes from tool_use to tool_result that waited on a
#          person: a permission the user decided (the result's permissionDecision source user_*) or a
#          tool named *AskUserQuestion; the span includes the tool's own run after the answer
#   cache  write=<tokens> read=<tokens> rewrites=<n>   — each message once; a rewrite: a message writing
#          over half its input to the cache (a context paid again after a pause or a restart); a
#          transcript's first message writes its context for the first time and is not one
#   reread  files=<n> reads=<n>   — files the Read tool read 3+ times in one transcript, and those reads;
#          --detail adds "reread_file <path> reads=<n>" lines: file names, for this machine only
#   turns  assistant=<n> tool_calls=<n>   — distinct messages and tool calls
# A result whose call is not in the files read (or before --since) is skipped; so is a line that is no
# record. Exit 1 when no transcript is found or a prefix is ambiguous, 2 on a usage error.
set -eu
usage() { sed -n '2,45s/^# \{0,1\}//p' "$0"; exit 2; }
arg=""; since=""; till=""; mode=one; detail=0; skip=0; proj=""
while [ $# -gt 0 ]; do
  case "$1" in
    --detail) detail=1 ;;
    --since) [ $# -ge 2 ] && [ "$mode" = one ] || usage; mode=since; since="$2"; shift ;;
    --until) [ $# -ge 2 ] && [ -z "$till" ] || usage; till="$2"; shift ;;
    --skip-tests) skip=1 ;;
    --project) [ $# -ge 2 ] && [ -z "$proj" ] && [ -n "$2" ] || usage; proj="$2"; shift ;;
    -*) usage ;;
    *) [ -z "$arg" ] || usage; arg="$1" ;;
  esac
  shift
done
if [ "$mode" = since ]; then [ -z "$arg" ] || usage
else [ -n "$arg" ] && [ -z "$till" ] && [ "$skip" = 0 ] && [ -z "$proj" ] || usage; fi
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"   # Claude Code's own override of ~/.claude
projects="$cfg/projects"

# the records on stdin, every transcript followed by a line holding only \001
insights() {
  SINCE="$since" UNTIL="$till" DETAIL="$detail" LC_ALL=C awk '
    BEGIN { since = substr(ENVIRON["SINCE"], 1, 19); until = substr(ENVIRON["UNTIL"], 1, 19); detail = ENVIRON["DETAIL"] + 0
      MK = "Blocked by safety-guard: "; NO = "\001"; q = sprintf("%c", 39)
      SEP = "[ \t\n\r;&|()<>" q "\"`,=]+" }
    # the record s own timestamp, outside "message" (as session-tokens): the first on the line when it
    # comes before "message", else the last; "" when the line has none
    function rects(s,   p, ts, r) { p = index(s, "\"message\":"); ts = ""
      if (match(s, /"timestamp":[ \t]*"[^"]*"/) && p > 0 && RSTART < p) ts = substr(s, RSTART, RLENGTH)
      else { r = s; while (match(r, /"timestamp":[ \t]*"[^"]*"/)) { ts = substr(r, RSTART, RLENGTH); r = substr(r, RSTART + RLENGTH) } }
      sub(/^"timestamp":[ \t]*"/, "", ts); sub(/"$/, "", ts); return ts }
    function days(y, m, d,   e, yoe, doy) { y -= (m <= 2); e = int(y / 400); yoe = y - e * 400
      doy = int((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5) + d - 1
      return e * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy - 719468 }
    # milliseconds since 1970 of a timestamp read as UTC, -1 when it is none
    function tms(ts,   f, s) {
      if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) return -1
      f = ""; if (substr(ts, 20, 1) == "." && match(substr(ts, 21), /^[0-9]+/)) f = substr(ts, 21, RLENGTH)
      s = ((days(substr(ts, 1, 4) + 0, substr(ts, 6, 2) + 0, substr(ts, 9, 2) + 0) * 24 + substr(ts, 12, 2)) * 60 + substr(ts, 15, 2)) * 60 + substr(ts, 18, 2)
      return s * 1000 + substr(f "000", 1, 3) }
    function num(u, k,   t) { if (!match(u, "\"" k "\":[ \t]*[0-9]+")) return 0
      t = substr(u, RSTART, RLENGTH); sub(/^[^:]*:[ \t]*/, "", t); return t + 0 }
    function starts(s, p) { return substr(s, 1, length(p)) == p }
    # s begins with a JSON string: its body as written (escapes kept); unterminated: the rest
    function jbody(s) { if (match(s, /^"([^"\\]|\\.)*"/)) return substr(s, 2, RLENGTH - 2); return substr(s, 2) }
    # the escapes \\ \" \/ \n \r \t read; any other (\u...) kept as written
    function unesc(s,   o, c) { o = ""
      while (match(s, /\\./)) { c = substr(s, RSTART + 1, 1); o = o substr(s, 1, RSTART - 1)
        if (c == "n") o = o "\n"; else if (c == "r") o = o "\r"; else if (c == "t") o = o "\t"
        else if (c == "\\" || c == "\"" || c == "/") o = o c; else o = o "\\" c
        s = substr(s, RSTART + 2) }
      return o s }
    function norm(s) { s = tolower(s); gsub(/\\/, "/", s); return s }
    # s[p] is "{": the index of its closing "}", 0 when there is none
    function objend(s, p,   d, c) { d = 0
      while (1) {
        if (!match(substr(s, p), /[{}"]/)) return 0
        p += RSTART - 1; c = substr(s, p, 1)
        if (c == "\"") { if (!match(substr(s, p), /^"([^"\\]|\\.)*"/)) return 0; p += RLENGTH; continue }
        if (c == "{") d++; else if (--d == 0) return p
        p++ } }
    # t in x as a whole word: no letter, digit or _ . - right before or after it
    function hasword(x, t,   i, p, b, a) { p = 0
      while ((i = index(substr(x, p + 1), t)) > 0) { p += i
        b = p > 1 ? substr(x, p - 1, 1) : ""; a = substr(x, p + length(t), 1)
        if (b !~ /[a-z0-9_.-]/ && a !~ /[a-z0-9_.-]/) return 1 }
      return 0 }
    # what a blocked call names, joined by SUBSEP: its file_path; in its command main, master and the
    # words with a / and 2 letters or digits (not /dev/...); the branch of "push while on <b>"
    function targets(c, f, reason,   o, x, n, i, w, W, t) { o = ""
      if (f != NO) { w = norm(unesc(f)); sub(/\/+$/, "", w); if (w != "") o = o SUBSEP w }
      if (c != NO) { x = norm(unesc(c)); gsub(SEP, " ", x); n = split(x, W, " ")
        for (i = 1; i <= n; i++) { w = W[i]
          if (w == "main" || w == "master") o = o SUBSEP w
          else if (index(w, "/") && substr(w, 1, 1) != "-") { sub(/\/+$/, "", w); t = w
            if (gsub(/[a-z0-9]/, "", t) >= 2 && substr(w, 1, 5) != "/dev/") o = o SUBSEP w } } }
      if (starts(reason, "push while on ")) o = o SUBSEP tolower(substr(reason, 15))
      return substr(o, 2) }
    # the guard s reason from the text after the marker
    function why(s,   i, j, o, pin) { s = unesc(s)
      if ((i = index(s, ". If this is a false positive")) > 0) s = substr(s, 1, i - 1)
      if ((i = index(s, "\n")) > 0) s = substr(s, 1, i - 1)
      if ((i = index(s, "\r")) > 0) s = substr(s, 1, i - 1)
      o = ""
      while ((i = index(s, "(")) > 0 && (j = index(substr(s, i), ")")) > 0) {
        pin = substr(s, i + 1, j - 2)
        o = o substr(s, 1, i - 1) ((index(pin, "/") || index(pin, "\\")) ? "(<path>)" : "(" pin ")")
        s = substr(s, i + j) }
      s = o s; gsub(/\t/, " ", s); sub(/[. ]+$/, "", s)
      return s == "" ? "?" : s }
    # the hook a hook error names: the last word of its command holding a / \ or . (the script), else its
    # first word, without folders; "hook" when the command is not shown
    function hook(b,   i, s, n, W, k, w) { i = index(b, "hook error: ["); if (!i) return "hook"
      s = substr(b, i + 13); i = index(s, "]: "); if (!i) return "hook"
      s = substr(s, 1, i - 1); gsub("[\"" q "]", "", s); n = split(s, W, " "); w = ""
      for (k = n; k >= 1; k--) if (W[k] ~ /[\/\\.]/) { w = W[k]; break }
      if (w == "" && n) w = W[1]
      gsub(/\\/, "/", w); sub(/.*\//, "", w); gsub(/[\t\n\r]/, " ", w)
      return w == "" ? "hook" : "hook " w }
    # a block or a refusal: counted under its kind and reason, open until the transcript s next call
    function block(id, kind, reason) { reason = kind "\t" reason; BC[reason]++; np++
      PR[np] = reason; PN[np] = CN[id]
      PK[np] = CC[id] != NO ? CC[id] : CF[id] != NO ? CF[id] : CI[id]
      PT[np] = targets(CC[id], CF[id], substr(reason, length(kind) + 2)) }
    function resolve(kind,   i) { for (i = 1; i <= np; i++) BK[PR[i], kind]++; np = 0 }
    # a transcript ends: open blocks stopped, its rereads counted
    function endfile(   k, d) { resolve("stopped")
      for (k in RD) if (RD[k] >= 3) { rf++; rr += RD[k]
        if (detail) { d = k; gsub(/[\t\n\r]/, " ", d); DL[++nd] = "reread_file\t" d "\treads=" RD[k] } }
      split("", RD); split("", perr); first1 = 0 }
    function assistant(   id, m, r, u, o, rest, s, tid, nm, p, e, inp, c, f, key, x, i, n, T, kind, k) {
      if (match($0, /"id":[ \t]*"msg_[^"]*"/)) {
        id = substr($0, RSTART, RLENGTH); sub(/^"id":[ \t]*/, "", id)
        m = ""; if (match($0, /"model":[ \t]*"[^"]*"/)) m = substr($0, RSTART, RLENGTH)
        if (m !~ /"<synthetic>"$/) {
          if (!(id in seen)) { seen[id] = 1; na++ }
          if ($0 ~ /"usage":[ \t]*[{]/) {
            # the message usage is the last on the line (a tool input may hold another)
            r = $0; u = ""; while (match(r, /"usage":[ \t]*[{]/)) { u = substr(r, RSTART); r = substr(r, RSTART + RLENGTH) }
            o = num(u, "output_tokens")
            if (!(id in out) || o > out[id]) { out[id] = o; ui[id] = num(u, "input_tokens")
              ur[id] = num(u, "cache_read_input_tokens"); uw[id] = num(u, "cache_creation_input_tokens") }
            if (!first1) { first1 = 1; first[id] = 1 }
          }
        }
      }
      rest = $0
      while (match(rest, /"type":[ \t]*"tool_use",[ \t]*"id":[ \t]*"[^"]*",[ \t]*"name":[ \t]*"[^"]*"/)) {
        s = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        match(s, /"id":[ \t]*"[^"]*"/); tid = substr(s, RSTART, RLENGTH); sub(/^"id":[ \t]*"/, "", tid); sub(/"$/, "", tid)
        match(s, /"name":[ \t]*"[^"]*"$/); nm = substr(s, RSTART, RLENGTH); sub(/^"name":[ \t]*"/, "", nm); sub(/"$/, "", nm)
        if (tid in used) continue
        used[tid] = 1; nc++
        inp = ""
        if (match(rest, /^,[ \t]*"input":[ \t]*[{]/)) { p = RLENGTH; e = objend(rest, p); inp = e ? substr(rest, p, e - p + 1) : substr(rest, p) }
        c = NO; f = NO
        if (match(inp, /"command":[ \t]*"/)) c = jbody(substr(inp, RSTART + RLENGTH - 1))
        if (match(inp, /"file_path":[ \t]*"/)) f = jbody(substr(inp, RSTART + RLENGTH - 1))
        CN[tid] = nm; CT[tid] = ms; CC[tid] = c; CF[tid] = f; CI[tid] = inp
        # the open blocks of this transcript: what this call does after them
        if (np) {
          key = c != NO ? c : f != NO ? f : inp
          x = norm(unesc(c != NO ? c : f != NO ? f : inp))
          for (i = 1; i <= np; i++) {
            if (nm == PN[i] && key == PK[i]) kind = "retried"
            else { kind = "changed"; n = split(PT[i], T, SUBSEP)
              for (k = 1; k <= n; k++) if (T[k] != "" && hasword(x, T[k])) { kind = "around"; break } }
            BK[PR[i], kind]++ }
          np = 0
        }
        # the tool s next call after an error: the same command (else input) again?
        if (nm in perr) { if (perr[nm] == (c != NO ? c : inp)) rep[tid] = 1; delete perr[nm] }
        if (nm == "Read" && f != NO) RD[unesc(f)]++
      }
      if ($0 ~ /"stop_reason":[ \t]*"end_turn"/) resolve("stopped")
    }
    function result(   id, nm, st, a, r, body, g, e) {
      if (!match($0, /"tool_use_id":[ \t]*"[^"]*"/)) return
      st = RSTART; id = substr($0, RSTART, RLENGTH); sub(/^"tool_use_id":[ \t]*"/, "", id); sub(/"$/, "", id)
      if (!(id in CN)) return
      nm = CN[id]
      if (ms >= 0 && CT[id] >= 0 && ms - CT[id] > 120000 && (nm ~ /AskUserQuestion$/ || $0 ~ /"permissionDecision":[ \t]*[{][^}]*"source":[ \t]*"user/)) { wt += ms - CT[id]; wn++ }
      if ($0 ~ /"is_error":[ \t]*true/) {
        if (match($0, /"type":[ \t]*"tool_result"/) && RSTART < st) st = RSTART
        body = ""; r = substr($0, st)
        if (match(r, /"content":[ \t]*/)) { r = substr(r, RSTART + RLENGTH)
          if (substr(r, 1, 1) == "[") { if (match(r, /"text":[ \t]*"/)) r = substr(r, RSTART + RLENGTH - 1); else r = "" }
          if (substr(r, 1, 1) == "\"") body = jbody(r) }
        g = 0
        if (starts(body, "PreToolUse:")) g = index(body, MK); else if (starts(body, MK)) g = 1
        if (g) block(id, "block", why(substr(body, g + length(MK))))
        else if (starts(body, "Permission to use ") && index(body, " has been denied")) block(id, "block", "deny rule")
        else if (starts(body, "PreToolUse:")) block(id, "refusal", hook(unesc(body)))
        else if (starts(body, "The user doesn" q "t want to proceed") || $0 ~ /"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"[^}]*"source":[ \t]*"user/) block(id, "refusal", "user")
        else if (starts(body, "Permission for this action was denied by the Claude Code auto mode classifier") || $0 ~ /"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"[^}]*"reasonType":[ \t]*"classifier"/) block(id, "refusal", "classifier")
        else if (starts(body, "Permission for this command was denied by a built-in") || $0 ~ /"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"[^}]*"reasonType":[ \t]*"safetyCheck"/) block(id, "refusal", "safety check")
        else if (starts(body, "[Request interrupted")) { }
        else if (starts(body, "Permission ") || $0 ~ /"permissionDecision":[ \t]*[{][^}]*"decision":[ \t]*"reject"/) block(id, "refusal", "other")
        else { TS[nm] = 1; e = unesc(body); sub(/[ \t\r\n]+$/, "", e)
          if (e ~ /^Exit code -?[0-9]+$/) TX[nm]++   # nothing but the exit code: no failure shown
          else { TE[nm]++; if (id in rep) TR[nm]++; perr[nm] = CC[id] != NO ? CC[id] : CI[id] } }
      }
      delete CN[id]; delete CT[id]; delete CC[id]; delete CF[id]; delete CI[id]; delete rep[id]
    }
    { sub(/\r$/, "")
      if ($0 == NO) { endfile(); next }
      if (substr($0, 1, 3) == "\357\273\277") $0 = substr($0, 4)   # a BOM
      isR = $0 ~ /"type":[ \t]*"tool_result"/
      if (!isR && $0 !~ /"type":[ \t]*"assistant"/) next
      ts = rects($0)
      if (since != "" && (ts == "" || substr(ts, 1, 19) < since)) next
      if (until != "" && substr(ts, 1, 19) >= until) next
      ms = tms(ts)
      if (isR) result(); else assistant() }
    END { endfile()
      if (!na && !nc) exit
      for (r in BC) printf "%s\tcount=%d changed=%d retried=%d around=%d stopped=%d\n", r, BC[r], BK[r, "changed"], BK[r, "retried"], BK[r, "around"], BK[r, "stopped"] | "LC_ALL=C sort"
      close("LC_ALL=C sort")
      for (t in TS) printf "tool_error\t%s\tcount=%d repeated=%d exit_only=%d\n", t, TE[t], TR[t], TX[t] | "LC_ALL=C sort"
      close("LC_ALL=C sort")
      printf "waiting\tminutes=%d calls=%d\n", int((wt + 30000) / 60000), wn
      for (id in out) { W += uw[id]; R += ur[id]; if (!(id in first) && uw[id] * 2 > ui[id] + uw[id] + ur[id]) rw++ }
      printf "cache\twrite=%.0f read=%.0f rewrites=%d\n", W, R, rw
      printf "reread\tfiles=%d reads=%d\n", rf, rr
      for (i = 1; i <= nd; i++) print DL[i] | "LC_ALL=C sort"
      close("LC_ALL=C sort")
      printf "turns\tassistant=%d tool_calls=%d\n", na, nc }'
}
# every file, then the \001 line (after a newline: a last line without one stays its own)
feed() { while IFS= read -r f; do [ -n "$f" ] || continue; cat "$f"; printf '\n\001\n'; done; }

# --skip-tests / --project: of the paths on stdin, those of the sessions kept, in their order. Per file its
# first cwd and its last name (customTitle / agentName), read with grep; a subagent's file is judged by its
# parent's transcript when that is listed (its own cwd also counts for the sandbox)
pick() {
  if [ "$skip" = 0 ] && [ -z "$proj" ]; then cat; return 0; fi
  local list; list="$(cat)"
  [ -n "$list" ] || return 0
  { printf '%s\n' "$list" | sed 's/^/F /'
    # /dev/null: a file grep never matches, so a list xargs leaves empty never reads stdin
    printf '%s\n' "$list" | tr '\n' '\0' | LC_ALL=C xargs -0 grep -a -H -m 1 -o '"cwd":"[^"]*"' /dev/null | sed 's/^/M /'
    printf '%s\n' "$list" | tr '\n' '\0' | LC_ALL=C xargs -0 grep -a -H -o -E '"(customTitle|agentName)":"[^"]*"' /dev/null | sed 's/^/M /'
  } | SKIP="$skip" PROJ="$proj" LC_ALL=C awk '
    # a path compared: \ read as /, repeated / as one, lower case, C:/x as /c/x, no trailing /
    function norm(p) { gsub(/\\/, "/", p); gsub(/\/+/, "/", p); p = tolower(p)
      if (p ~ /^[a-z]:\//) p = "/" substr(p, 1, 1) substr(p, 3)
      sub(/\/$/, "", p); return p }
    # w in s as a whole word: no letter, digit, _ or - right before or after it
    function word(s, w,   i, p, b, a) { p = 0
      while ((i = index(substr(s, p + 1), w)) > 0) { p += i
        b = p > 1 ? substr(s, p - 1, 1) : ""; a = substr(s, p + length(w), 1)
        if (b !~ /[a-z0-9_-]/ && a !~ /[a-z0-9_-]/) return 1 }
      return 0 }
    # a probe or self-test session by its name: probe, selftest or self-test as a word before the first
    # colon, or a task #st<n>; the title after the colon never counts (a task about a self-test is work)
    function tested(n,   v, i, h) { v = tolower(n); i = index(v, ":"); h = i ? substr(v, 1, i - 1) : v
      return v ~ /^#st[0-9]/ || word(h, "probe") || word(h, "selftest") || word(h, "self-test") }
    function sandbox(c) { return norm(c) ~ /\/coordinator-selftest(\/|$)/ }
    function inside(c) { if (c == "") return 0; c = norm(c); return c == R || substr(c, 1, length(R) + 1) == R "/" }
    BEGIN { skip = ENVIRON["SKIP"] + 0; R = ENVIRON["PROJ"]; if (R != "") R = norm(R) }
    $1 == "F" { f[++n] = substr($0, 3); listed[f[n]] = 1; next }
    $1 == "M" { s = substr($0, 3); i = index(s, ".jsonl:\""); if (!i) next
      p = substr(s, 1, i + 5); m = substr(s, i + 7)
      if (substr(m, 1, 7) == "\"cwd\":\"") { if (!(p in cwd)) { v = substr(m, 8); sub(/"$/, "", v); cwd[p] = v } }
      else { v = m; sub(/^"[A-Za-z]*":"/, "", v); sub(/"$/, "", v); nm[p] = v }
      next }
    END { for (k = 1; k <= n; k++) { p = f[k]; q = p
        if (match(p, /\/subagents\/[^\/]*\.jsonl$/) && (substr(p, 1, RSTART - 1) ".jsonl") in listed) q = substr(p, 1, RSTART - 1) ".jsonl"
        cq = (q in cwd) ? cwd[q] : ""; cp = (p in cwd) ? cwd[p] : ""; nq = (q in nm) ? nm[q] : ""
        if (skip && (tested(nq) || sandbox(cq) || sandbox(cp))) continue
        if (R != "" && !inside(cq != "" ? cq : cp)) continue
        print p } }'
}
# a --since / --until value as YYYY-MM-DDTHH:MM:SS[...] in UTC (the awk reads its first 19 characters)
utc() {
  local v="$2" bad="$1 needs YYYY-MM-DDTHH:MM:SS in UTC (Z or nothing after it) or Unix seconds, got $2"
  case "$v" in
    '' | *[!0-9]*)
      re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z?$'   # no other offset
      [[ $v =~ $re ]] || { echo "$bad" >&2; return 2; }
      printf '%s\n' "$v" ;;
    *)
      # Unix seconds (the status line's resets_at): GNU date reads @<n>, BSD date -r <n>
      [ ${#v} -le 10 ] || { echo "$bad" >&2; return 2; }
      if date --version >/dev/null 2>&1; then date -u -d "@$v" +%Y-%m-%dT%H:%M:%S
      else date -u -r "$v" +%Y-%m-%dT%H:%M:%S; fi ;;
  esac
}

if [ "$mode" = since ]; then
  since="$(utc --since "$since")" || exit 2
  if [ -n "$till" ]; then till="$(utc --until "$till")" || exit 2; fi
  [ -d "$projects" ] || { echo "no transcripts in $projects" >&2; exit 1; }
  # in the order of their paths, so that the .ps1 reads them in the same order
  find "$projects" -name '*.jsonl' -type f | LC_ALL=C sort | pick | feed | insights
  exit 0
fi
main=""
if [ -f "$arg" ]; then main="$arg"; elif [ -d "$projects" ]; then
  # the full id, else a unique prefix (claude --bg and claude agents print 8 characters)
  main="$(find "$projects" -maxdepth 2 -name "$arg.jsonl" 2>/dev/null | head -n 1)"
  if [ -z "$main" ]; then
    found="$(find "$projects" -maxdepth 2 -name "$arg*.jsonl" 2>/dev/null || true)"
    if [ "$(printf '%s' "$found" | grep -c .)" -gt 1 ]; then
      # ids only: the folder names would show other projects
      echo "ambiguous id $arg:" >&2; printf '%s\n' "$found" | sed 's|.*/||; s|\.jsonl$||' | LC_ALL=C sort >&2; exit 1
    fi
    main="$found"
  fi
  if [ -z "$main" ]; then
    # a subagent's agentId (the Agent tool's result): its transcript sits in its parent's subagents/ folder
    found="$(find "$projects" -mindepth 4 -maxdepth 4 -path '*/subagents/*' -name "agent-$arg*.jsonl" 2>/dev/null || true)"
    if [ "$(printf '%s' "$found" | grep -c .)" -gt 1 ]; then
      echo "ambiguous id $arg:" >&2; printf '%s\n' "$found" | sed 's|.*/agent-||; s|\.jsonl$||' | LC_ALL=C sort >&2; exit 1
    fi
    main="$found"
  fi
fi
[ -n "$main" ] && [ -f "$main" ] || { echo "no transcript for $arg" >&2; exit 1; }
sub="${main%.jsonl}/subagents"
# the transcript first, then its subagents' in the order of their names
{ printf '%s\n' "$main"; [ -d "$sub" ] && find "$sub" -maxdepth 1 -name '*.jsonl' -type f | LC_ALL=C sort; true; } | feed | insights

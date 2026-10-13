# Feature test — a prompt for a tester session

Give this file, with one group or feature ID filled in below, to a fresh session (a subagent or a
separate Claude session; a strong reasoning model). It tests the core against the promises in
[FEATURES.md](../FEATURES.md) and returns a report. It changes nothing in the core.

---

You are an independent tester of **claude-coordinator**, a reusable coordinator core for Claude Code
sessions (`CORE.md`, `TOOLKIT.md`, `procedures/`, `roles/`, `scripts/`). Your job is to find where the
core does not do what it promises. You did not write it; do not assume it is right.

**Scope:** the features of group `<GROUP>` (or the feature IDs `<IDs>`) in `FEATURES.md`.

**How:**
1. Read `FEATURES.md` (the header and your blocks), then every file your blocks name — the whole file
   where a script is involved, the named sections otherwise. Read `CORE.md` §1 (the hard rules).
2. For each `promises` line, try to falsify it. Start with the features whose `not covered` says *no
   automated check* — they are the likeliest holes.
   - **Scripts:** run them (`bash scripts/<x>.sh`, and on Windows `powershell -NoProfile
     -ExecutionPolicy Bypass -File scripts/<x>.ps1` and `pwsh` where present) on throwaway git
     repositories you create in a temporary folder. Edge cases: spaces and non-ASCII in paths, CRLF,
     empty or missing inputs, a prefix that matches twice, a branch name like a flag, an offline remote,
     Windows PowerShell 5.1 vs 7, bash 3.2 syntax. Compare the `.sh` and `.ps1` outputs: the core
     promises they match.
   - **The safety guard:** feed it JSON tool calls on stdin exactly as Claude Code does (see
     `tests/safety-guard/`) and look for a protected push, a force push or a destructive removal that
     passes, and for a harmless command it blocks. Deliberate evasion (`eval`, aliases, a branch name in a
     variable) is out of scope by design — report it only if a plain, ordinary command gets through.
   - **Rules (documents):** look for two rules that contradict each other, a rule a session cannot
     follow with the tools it has, a step that refers to a file, flag or section that does not exist,
     and a promise in `FEATURES.md` that the named files do not actually make.
   - The existing tests (`tests/`, `.github/workflows/check-core.yml`) show what is covered; test
     around them, not through them again.
3. Keep a short log of what you tried, so the report can show coverage.

**Limits — hard:**
- Never modify, commit or push anything in this repository; work on copies in a temporary folder.
- No `git push` anywhere except to a bare repository you created in that temporary folder; no
  `gh issue`, `gh pr` or any other write to GitHub; no real `claude --bg` sessions (use a stub `claude`
  on `PATH` as `tests/workers/run.sh` does).
- Never `rm -rf`; remove only the temporary folder you created, by its exact path.
- No secrets, no files outside this repository and your temporary folder.

**Report** (your final answer, nothing else):

```
## Findings
### <feature ID> — <one line>
- promise: <the promises line it breaks, quoted>
- severity: critical (safety, data loss) / high (wrong result, blocked work) / medium / low (wording)
- confidence: certain (reproduced) / likely / suspicion
- reproduce: <exact commands, from an empty temporary folder>
- expected: <…>
- actual: <… exact output, exit code>
- suggestion: <optional, smallest fix>

## Held
<feature ID>: <each promise you tried to break and how; one line each>

## Not tested
<feature ID>: <what and why (needs a real session, a code host, a device…)>
```

Report only what you reproduced or can point to in the text; mark anything else `suspicion`. A finding
without a way to reproduce it or a quote that shows it is not a finding.

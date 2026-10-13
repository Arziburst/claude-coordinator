# Core findings — <project name>

Problems whose cause is the coordinator core itself, found while working on this project
([procedures/CORE-FINDINGS.md](procedures/CORE-FINDINGS.md)). This file lives in the coordinator's private
state repository (`coordinator/CORE-FINDINGS.md`), never in the project and never in the core.

- **A finding** — a core rule could not be followed; a core script behaved wrongly; a safeguard or
  check silently did not work; the core had no step for a real situation; a role could not do what the
  core requires of it. **The test:** would the same core rule, script or template fail the same way in
  any project? Then it is a core finding; if only this project's wrapper or setting broke, it is a
  project issue (some are both: fix the project, record the core's gap).
- **Written at the moment** it happens, with evidence that can be re-checked (a command and its exit
  code, the exact error, a commit, a CI run, a session's hook record), **before** working around it;
  the workaround goes into the row too.
- **Statuses:** `new` → `sent #<issue>` (filed to claude-coordinator) or `discussed` → `sent <date>`
  (handed over by the owner) → `fixed <core commit>` (proven here after an update) · `fixed upstream
  <commit>` (fixed before it was sent: update the core) · `dropped` (why) ·
  `not core` (why).

| id | date | core | trigger | what happened (evidence) | workaround | status |
|---|---|---|---|---|---|---|

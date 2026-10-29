# Core findings — fixture

| id | date | core | trigger | what happened (evidence) | workaround | status |
|---|---|---|---|---|---|---|
| CF-1 | 2026-09-05 | 1ebe968 | start-worker | the brief was cut (exit 1) | a shorter brief | fixed 7c2d4a9 |
| CF-2 | 2026-09-24 | 1ebe968 | merge-queue | a stale lock after a crash | removed the lock by hand | new |
| CF-3 | 2026-09-26 | 1ebe968 | guard | a push to a feature branch blocked | pushed by the owner | sent #12 |
| CF-4 | 2026-10-01 | 1ebe968 | retro | the week began on Sunday | none | discussed |
| CF-5 | 2026-10-03 | 7c2d4a9 | check-contract | a block list read as one item | inline list | fixed 7c2d4a9 |
| CF-6 | 2026-10-04 | 7c2d4a9 | session-insights | counted a probe | none | dropped (a duplicate of CF-4) |
| CF-7 | 2026-10-05 | 7c2d4a9 | start-worker | the wrong model | none | not core (a project setting) |
| CF-8 | 2026-10-09 | 7c2d4a9 | cleanup-worker | a merged branch kept | removed by hand | sent 2026-10-10 |
| CF-9 | 2026-10-11 | 7c2d4a9 | guard | a timeout under load | one retry | fixed upstream 9e1b3f0 |

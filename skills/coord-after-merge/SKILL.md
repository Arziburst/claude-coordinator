---
name: coord-after-merge
description: 'Coordinator only - right after every merge (the merge queue prints MERGED and AFTER MERGE), before anything else.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read the event table in CORE §4 of `coordinator/core/CORE.md`, the row "A task is accepted, merged or
dropped", and do every item of it - the queue's `AFTER MERGE` line lists them. The task row of the run
log is written by `run-stats --task <n> ... --append` (CORE §7). Never filter the queue's AFFECTED lines out.

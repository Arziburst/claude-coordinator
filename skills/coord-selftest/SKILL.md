---
name: coord-selftest
description: 'Coordinator only - when the self-test runs: after an update of the core, on a new machine, or when the owner asks for it.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read `coordinator/core/procedures/SELFTEST.md` and run it as written; its evidence branches go to the state
repository, its result into `coordinator/CHECKLIST.md`.

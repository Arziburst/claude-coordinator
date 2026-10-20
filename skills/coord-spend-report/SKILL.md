---
name: coord-spend-report
description: 'Coordinator only - when the owner asks for a spend report, or what the work cost; it never runs by itself.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read CORE §7a in `coordinator/core/CORE.md` ("Analysis, when the owner asks") and the run-stats lines of
`coordinator/core/TOOLKIT.md` *Usage*; the numbers come from `run-stats` on `coordinator/RUNS.tsv`, never by hand.

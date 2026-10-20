---
name: coord-task-start
description: 'Coordinator only - every time a task is about to start (before start-worker, or a tester or lead run): the contract, conflict foresight, the tester, the subscription, the journal.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read the event table in CORE §4 of `coordinator/core/CORE.md`, the row "A task starts", and the continuous
work steps 2-4 under it; do every item of the row. start-worker prints the conflict foresight
(`foresight:` lines) and the subscribe line: act on both.

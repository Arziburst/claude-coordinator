---
name: coord-task-start
description: 'Coordinator only - every time a task is about to start (before start-worker, or a tester or lead run): the contract, conflict foresight, the tester, the watch list, the journal.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read the event table in CORE §4 of `coordinator/core/CORE.md`, the row "A task starts", and the continuous
work steps 2-4 under it; do every item of the row. start-worker prints the conflict foresight
(`foresight:` lines) and the subscribe line: act on the foresight; a session that reports by message
goes on the watch list (`coordinator/watch.txt`, its short id or full name) instead of being subscribed,
and one `watch-sessions --list coordinator/watch.txt` runs in the background unless one already runs
(CORE §4 step 4 *Control*); the subscribe line is used only for a session no message is expected from.
Before start-worker, run `scripts/check-contract <contract> --runs coordinator/RUNS.tsv` (`--kind <k>` when
the contract has no `kind:` field; .ps1: `-Runs`, `-Kind`) and copy the plan line it prints
(`<file>: run-stats <kind>/<model>: …`) into the plan next to the budget: a budget WARN is explained in the
brief; a thin history's guess is multiplied by the ratio it prints and marked `guess` (CORE §7a).

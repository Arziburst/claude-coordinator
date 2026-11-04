---
name: coord-after-compaction
description: 'Coordinator only - right after the conversation was compacted (a summary replaced the history), before the next step.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The row named below wins over this summary: read it from disk with the Read tool, then act on it.

Read the event table in CORE §4 of `coordinator/core/CORE.md`, the row "The conversation is compacted", and
do it: CORE's §1 and the table, PROJECT.md, BINDINGS.md and the journal's open questions re-read from disk,
the rest of CORE when a topic needs it, then every duty of the table not done since the last journal line.

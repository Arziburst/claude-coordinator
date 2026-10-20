---
name: coord-handoff
description: 'Coordinator only - when the owner says "prepare a handoff", or a session starts on a new machine from the state repository.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read `coordinator/core/procedures/HANDOFF.md` (CORE §12b). A handoff is prepared only on the owner's command.

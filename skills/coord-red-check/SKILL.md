---
name: coord-red-check
description: 'Coordinator only - every time a CI check, the merge queue (FAILED) or the main line goes red, before anyone acts on it.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read "A red check" in CORE §4, step 4 of the continuous work, and CORE §1.7 in `coordinator/core/CORE.md`:
classify it first (cancelled, code, infrastructure, flake), never merge over it.

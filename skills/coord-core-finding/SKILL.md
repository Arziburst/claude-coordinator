---
name: coord-core-finding
description: 'Coordinator only - the moment a core rule, script or check fails us (a rule that cannot be followed, a script that behaves wrongly, a safeguard that does not work, a role that cannot do what the core asks), and when a finding is sent or closed.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read `coordinator/core/procedures/CORE-FINDINGS.md` (CORE §10): the row in `coordinator/CORE-FINDINGS.md` at
once, with evidence and before any workaround; the issue as the owner chose at init.

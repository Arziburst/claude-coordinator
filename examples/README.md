# Examples — illustrations, not rules

These folders show what filled layers look like for two very different projects. They are **not**
defaults and never rules for another project (CORE §1, *Definitions*): every project gets its own answers
from the init quiz. In particular the Arx example is the swarm preset (own project, autopilot,
coordinator merges) — wrong for client work.

- `nextjs-supabase/` — commercial client web app in the strict preset with production writes overridden to standard: humans merge,
  "announce and wait", no autopilot; `settings.json` lists candidate deny rules for the cautious override
  (adapt MCP tool names).
- `arx-fatalis-vr/` — own game project: swarm, autopilot, the coordinator merges on green CI.

# claude-coordinator

> **If you are a Claude session and were given a link to this repository: you are now the
> coordinator.**
> 1. Read [CORE.md](CORE.md) completely
>    (raw: `https://raw.githubusercontent.com/Arziburst/claude-coordinator/main/CORE.md`).
>    Its rules override your default habits; §1 are hard rules.
> 2. Initialize per CORE §2 in the project you are working in: find its `coordinator/PROJECT.md` and
>    `coordinator/BINDINGS.md`. Filled → read them and the project's state. Missing → adopt the
>    project's existing rules (CORE §2.5) or run the setup interview (CORE §3) using
>    [PROJECT.template.md](PROJECT.template.md) and [BINDINGS.template.md](BINDINGS.template.md), and
>    write them into the project's `coordinator/` folder after the owner's yes.
> 3. Tell the owner in one short message that you are the coordinator, what you found and what you
>    need. Then wait for "start a new cycle" or the owner's instruction (CORE §1.2: a question is not an
>    order).

A reusable **coordinator** for Claude Code: one Claude session that runs a software project — plans the
work, delegates it to worker sessions, controls and reviews the result, integrates it per the project's
rules and reports to the owner. Works for any project and stack, solo or in a team, own or client work.

## Layers
- [CORE.md](CORE.md) — who the coordinator is and how it works; the same everywhere.
- [PROJECT.template.md](PROJECT.template.md) → `coordinator/PROJECT.md` in the project — how this
  project works: the cycle, tracking, the change flow, review, merging, acceptance, environments,
  resources, budget, voice, language, MCP. Filled in a setup interview with the owner.
- [BINDINGS.template.md](BINDINGS.template.md) → `coordinator/BINDINGS.md` — the concrete commands and tools.

## Examples
- [examples/nextjs-supabase/](examples/nextjs-supabase/) — client web app (Next.js + Supabase, Vercel, a
  team with a business analyst, humans merge, "announce and wait" cycle).
- [examples/arx-fatalis-vr/](examples/arx-fatalis-vr/) — own game project (VR port, rush mode, autopilot
  cycle with ~10 parallel workers).

## Use
- **Any project:** open a Claude Code session in the project and give it the link to this repository —
  it becomes the coordinator and initializes. Or copy this repository into the project as
  `coordinator/` and add to the project's `CLAUDE.md`: `The coordinator session follows
  coordinator/CLAUDE.md.`
- **"Start a new cycle"** — the coordinator runs the project's cycle recipe (CORE §4).
- **"Coordinator, what is your task?"** — it explains its full flow and the rules in effect (CORE §13).

## Changing the core
Universal lessons go into `CORE.md` with the owner's yes (CORE §10); project lessons stay in the
project's `coordinator/PROJECT.md`.

# claude-coordinator

> **If you are a Claude session and were given a link to this repository: you are now the
> coordinator.**
> 1. Read [CORE.md](CORE.md) completely
>    (raw: `https://raw.githubusercontent.com/Arziburst/claude-coordinator/main/CORE.md`).
>    Its rules override your default habits; §1 are hard rules.
> 2. Follow **the one start sequence** in CORE §2: identity → one coordinator per project → find the
>    project files → learn the context (sessions, PRs, history) → open questions → the **init quiz**
>    (multiple choice with a recommended option; first "commercial or non-commercial?", "swarm or
>    sequential?") → platform and safety → **dry run** → **wait** for the owner's explicit "start a new
>    cycle". Start no work until every quiz question is answered (CORE §1.12); never start a cycle on
>    your own.
> 3. Templates: [PROJECT.template.md](PROJECT.template.md), [BINDINGS.template.md](BINDINGS.template.md);
>    machine mechanics and the new-machine checklist: [TOOLKIT.md](TOOLKIT.md). The
>    [examples](examples/) are illustrations, never rules.

A reusable **coordinator** for Claude Code: one Claude session that runs a software project — plans the
work, delegates it to worker sessions, controls and reviews the result, integrates it per the project's
rules and reports to the owner. Works for any project and stack, solo or in a team, own or client work.

## Layers
- [CORE.md](CORE.md) — who the coordinator is and how it works; the same everywhere.
- [PROJECT.template.md](PROJECT.template.md) → `coordinator/PROJECT.md` in the project — how this
  project works: the cycle, tracking, the change flow, review, merging, acceptance, environments,
  resources, budget, voice, language, MCP. Filled in a setup interview with the owner.
- [BINDINGS.template.md](BINDINGS.template.md) → `coordinator/BINDINGS.md` — the concrete commands and tools.

## Toolkit (any machine — Windows, macOS, Linux)
- [TOOLKIT.md](TOOLKIT.md) — Claude Code mechanics for a coordinator: named background workers,
  messages, the tick, safety rules and hooks, limits, platform notes, and the **new machine checklist**.
- [scripts/](scripts/) — reference scripts (bash; Git Bash on Windows): `start-worker.sh` (named session
  in its own worktree), `cleanup-worker.sh` (only clean and pushed work), `hooks/safety-guard.sh`
  (guards only the irreversible: pushes / force-pushes / deletes of main, mirror pushes, removing `/`,
  home or a worktree by hand — work branches stay free), `statusline.sh` (saves
  usage limits for the coordinator). Run with `--dry-run` first on a new machine.
- [settings.example.json](settings.example.json) — the worker safety file (passed by `start-worker.sh
  --safety`): protected-branch denies, the hook and its self-test, messages accepted — the autonomous
  baseline; the cautious level adds denies.

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
- **Moving to another machine** — say "prepare a handoff": the coordinator pushes the work and saves
  its state to the project's private state repository (CORE §12b, `state-repo/README.template.md`,
  `HANDOFF.template.md`). On the new machine give a session only that repository's link.
- **"Coordinator, what is your task?"** — it explains its full flow and the rules in effect (CORE §13).

## Changing the core
Universal lessons go into `CORE.md` with the owner's yes (CORE §10); project lessons stay in the
project's `coordinator/PROJECT.md`.

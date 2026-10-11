# Coordinator state — <project name>

> **If you are a Claude session and were given a link to this repository: you are now the coordinator
> of <project name>, continuing on a new machine.**
> 1. Read the coordinator core — from `core/` in this repository if `PROJECT.md` records a **local
>    core**, otherwise from
>    `https://raw.githubusercontent.com/Arziburst/claude-coordinator/main/CORE.md` (and `TOOLKIT.md`
>    for machine mechanics). Its rules override your default habits; §1 are hard rules.
> 2. This repository is the project's coordinator state (CORE §12b): read `HANDOFF.md` first, then
>    `PROJECT.md`, `BINDINGS.md`, `LOG.md`.
> 3. Run the start sequence (CORE §2) with this context: clone the project repository named in
>    `BINDINGS.md`, re-detect the platform and every row marked "re-detect", check the logins and
>    accesses listed in `HANDOFF.md`, set up the safety rules, confirm the quiz briefly, then a **dry
>    run** showing which interrupted tasks you would restart — and **wait** for the owner.
> 4. Committed locally at the end of every cycle; pushed to this remote only on the owner's command
>    ("prepare a handoff" / "update the state repo").

**Private.** This repository holds internal project information — never make it public, never share it
with the client.

| File | What |
|---|---|
| `HANDOFF.md` | the snapshot at the last handoff: tasks in flight, merge queue, open questions, logins needed |
| `PROJECT.md` | the project rules (layer 2) |
| `BINDINGS.md` | tools and commands (layer 3); rows marked "re-detect" depend on the machine |
| `LOG.md` | the coordinator's journal |
| `core/` | the local copy of the coordinator core (only with a local core), at the commit recorded in `PROJECT.md` |

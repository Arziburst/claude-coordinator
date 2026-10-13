# Coordinator state — <project name>

> **If you are a Claude session and were given a link to this repository: you are now the coordinator
> of <project name>, continuing on a new machine.**
> 1. Read the coordinator core from `core/` in this repository (`core/CORE.md`, and `core/TOOLKIT.md`
>    for machine mechanics). Its rules override your default habits; §1 are hard rules.
> 2. This repository is the project's coordinator state (CORE §12b): read `HANDOFF.md` first, then
>    `PROJECT.md`, `BINDINGS.md`, `LOG.md`.
> 3. Run the start sequence (CORE §2) with this context: clone the project repository named in
>    `BINDINGS.md`, re-detect the platform and every row marked "re-detect", check the logins and
>    accesses listed in `HANDOFF.md`, set up the safety rules, confirm the quiz briefly, then a **dry
>    run** showing which interrupted tasks you would restart — and **wait** for the owner.
> 4. One branch, `state` (also the default one). Committed at every change and pushed to this remote at the events of CORE §12b — session start, a task done, a decision, a handoff; otherwise at most every 15 minutes (`git pull --ff-only`
>    first, never force-pushed; not fast-forwardable → stop and ask the owner). Only one machine's
>    coordinator writes it (`core/procedures/HANDOFF.md`).

**Private.** This repository holds internal project information — never make it public, never share it
with the client.

| File | What |
|---|---|
| `HANDOFF.md` | the snapshot at the last handoff: tasks in flight, merge queue, open questions, logins needed |
| `PROJECT.md` | the project rules (layer 2) |
| `BINDINGS.md` | tools and commands (layer 3); rows marked "re-detect" depend on the machine |
| `LOG.md` | the coordinator's journal |
| `RUNS.tsv` | the run log: model, cost, tokens, result, and start, wall and active minutes per run (CORE §7) |
| `ROUTING.md` | the model and effort per kind of task, adjusted automatically from the run log (CORE §7) |
| `ESCAPES.tsv` | bugs found after their change was merged: date, bug, the task that introduced it (or unknown), who found it (CORE §12) |
| `CORE-FINDINGS.md` | the core's own failures found here, sent to claude-coordinator and proven fixed after an update (core/procedures/CORE-FINDINGS.md) |
| `CHECKLIST.md` | the one-time settings and checks that ran here, per project and per machine (`core/ONE-TIME.md`) |
| `core/` | the local copy of the coordinator core, at the commit recorded in `PROJECT.md` |
| `SOURCES.md`, `sources/` | the source catalog and the files the owner gave (masked summaries; raw files never leave this private repository) |
| `TASKS.md` | only without a tracker: the tasks and their statuses |

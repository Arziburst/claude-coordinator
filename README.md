# claude-coordinator

> **If you are a Claude session and were given a link to this repository: you are now the
> coordinator.**
> 1. Read [CORE.md](CORE.md) completely
>    (raw: `https://raw.githubusercontent.com/Arziburst/claude-coordinator/main/CORE.md`).
>    Its rules override your default habits; §1 are hard rules. In a project that already has
>    `coordinator/core/`, that local copy is the core you follow (CORE §2 step 3).
> 2. Follow **the one start sequence** in CORE §2: identity → one coordinator per project → find the
>    project files → learn the context (sessions, PRs, history) → open questions → the **init quiz**
>    (multiple choice with a recommended option; first "strictness: swarm, standard or strict?") → platform and safety → **dry run** → **wait** for the owner's first task or
>    batch command. Start no work until every quiz question is answered (CORE §1.12); never start work on
>    your own.
> 3. Templates: [PROJECT.template.md](PROJECT.template.md), [BINDINGS.template.md](BINDINGS.template.md);
>    machine mechanics and the new-machine checklist: [TOOLKIT.md](TOOLKIT.md).

A reusable **coordinator** for Claude Code: one Claude session that runs a software project — plans the
work, delegates it to worker sessions, controls and reviews the result, integrates it per the project's
rules and reports to the owner. Works for any project and stack, solo or in a team, own or client work.

## Layers
- [CORE.md](CORE.md) — who the coordinator is and how it works; the same everywhere.
- [PROJECT.template.md](PROJECT.template.md) → `coordinator/PROJECT.md` in the project — how this
  project works: the work mode, tracking, the change flow, review, merging, acceptance, environments,
  resources, budget, voice, language, MCP. Filled in a setup interview with the owner.
- [BINDINGS.template.md](BINDINGS.template.md) → `coordinator/BINDINGS.md` — the concrete commands and tools.
- [CONTRACT.md](CONTRACT.md) — the unit of delegated work: the contract a worker gets, the report it
  returns, and the evidence classes (oracle / review / claim).
- [FEATURES.md](FEATURES.md) — the map of every feature the core implements: where it is defined, what
  triggers it, what it promises, what tests it and what is not covered — for sessions that test one
  feature at a time, and for people; `scripts/check-core` keeps it in sync.
- [ONE-TIME.md](ONE-TIME.md) — one-time settings and checks, like migrations: each project's
  `coordinator/CHECKLIST.md` records which ran, so "update the core" asks only the new ones.
- [roles/](roles/) — role definitions: [worker.md](roles/worker.md) implements a contract,
  [lead.md](roles/lead.md) runs a large task through its own workers and returns one PR,
  [tester.md](roles/tester.md) writes its failing tests first,
  [verifier.md](roles/verifier.md) reviews it independently, [scout.md](roles/scout.md) condenses long
  logs and threads on the light model, [researcher.md](roles/researcher.md) returns a catalog of what to take.
- [procedures/](procedures/) — parts of the core read only when needed: the init quiz
  ([INIT.md](procedures/INIT.md)), the move to another machine ([HANDOFF.md](procedures/HANDOFF.md)), the answer to
  "what is your task?" ([WHAT-IS-YOUR-TASK.md](procedures/WHAT-IS-YOUR-TASK.md)), "settings"
  ([SETTINGS.md](procedures/SETTINGS.md)), the self-test ([SELFTEST.md](procedures/SELFTEST.md)), "update the core"
  ([UPDATE-CORE.md](procedures/UPDATE-CORE.md), with [MIGRATE-LAYOUT.md](procedures/MIGRATE-LAYOUT.md)), the sources of
  truth, the source catalog and projects without a tracker or git ([SOURCES.md](procedures/SOURCES.md)), the
  core's own failures sent to its maintainer and proven fixed ([CORE-FINDINGS.md](procedures/CORE-FINDINGS.md)).

## Toolkit (any machine — Windows, macOS, Linux)
- [TOOLKIT.md](TOOLKIT.md) — Claude Code mechanics for a coordinator: named background workers,
  messages, the tick, safety rules and hooks, limits, platform notes, and the **new machine checklist**.
- [scripts/](scripts/) — reference scripts, one style (TOOLKIT *Scripts*: a `.sh` + `.ps1` pair, nothing to install): `start-worker` (named session
  in its own worktree), `cleanup-worker` (only clean and pushed work), `hooks/safety-guard`
  (guards only the irreversible: pushes / force-pushes / deletes of main, mirror pushes, removing `/`,
  home or a worktree by hand — work branches stay free), `selftest` (the scripted steps of the
  self-test: checks, environment, the evidence branches in the state repository; a sandbox for the
  core itself), `statusline`
  (the status line `Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%`, offered in the init quiz;
  also saves usage limits for the coordinator). Run with `--dry-run` / `-DryRun` first on a new machine.
- [settings.example.json](settings.example.json) / [settings.example.windows.json](settings.example.windows.json)
  — the worker safety file (passed by `start-worker --safety` / `-Safety`): protected-branch denies, the hook and its self-test, messages accepted — the swarm and
  standard baseline; the strict preset and the cautious override add denies.

## Use
- **Any project:** open a Claude Code session in the project and give it the link to this repository —
  it becomes the coordinator and initializes. The coordinator keeps its files in the project's
  `coordinator/` folder, its own local git repository hidden from the project's git (CORE §12b).
- **The core is a local copy** in `coordinator/core/`, like a pinned package: editable for that project;
  at start the coordinator says when upstream is newer, and "update the core" brings the changes in on
  command, with an impact report first.
- **Give it work** — name a task (work mode *by task*), or say the batch command ("start a new cycle" by default) to run
  the project's batch recipe (*batch*). Cleanup, syncing the state and core reports run on events in either mode (CORE §4).
- **Moving to another machine** — `coordinator/` is pushed at every event that matters (CORE §12b) to a private remote, the
  project's state repository, if the owner chose one at init; say "prepare a handoff" before a move: the
  coordinator pushes the work in flight and writes `HANDOFF.md` (CORE §12b, `state-repo/README.template.md`,
  `HANDOFF.template.md`). On the new machine give a session only that repository's link.
- **"Coordinator, what is your task?"** — it explains its full flow and the rules in effect (CORE §13).

## Changing the core
Issues titled `[core-report]` come from projects' coordinators (a workflow labels them `core-report`):
reproduce, fix in a PR that names the issue, close it with the fixing commit, keep project details out
([procedures/CORE-FINDINGS.md](procedures/CORE-FINDINGS.md) §4). Universal lessons go into `CORE.md` with the owner's yes (CORE §10); project lessons stay in the
project's `coordinator/PROJECT.md`. Before a pull request: `scripts/check-core.sh` (Windows:
`scripts\check-core.ps1`). A new or changed script keeps the one style of TOOLKIT *Scripts*. A change
to a script's required arguments or to the output a project's wrapper reads puts a line **starting
with** `Breaking for project wrappers: <script> - <what changed, what a wrapper must do>` into its
commit message (the squash commit's body), so "update the core" finds it with an anchored grep
(UPDATE-CORE step 3); a message that only mentions the rule never starts a line with it.

# Project rules — <project name>

Layer 2 of the coordinator (see `CORE.md`). Filled through the init quiz (procedures/INIT.md §3),
revised whenever the owner changes how the project works. Every row: the question, **this project's
answer**, and a default — per the strictness preset (CORE §3) where they differ. Only a few rows are
**asked** (INIT 3.1); the rest are **found** in the project and confirmed in one table (3.2) or filled
**by default** (3.3), and all of them are shown in one summary for the owner's yes. A row marked *(if
any)* stays `n/a` when the project has no such thing. Work starts only when no `<fill>` is left and the
owner said yes to the summary (CORE §1.12).

## Settings
What "settings" shows (procedures/SETTINGS.md), kept in one place: **Source** is `preset`, `default`,
`owner, <date>` or `override`; **Since** the date it took this value. "Change X to Y" edits a row here
on the owner's yes. The sections below hold the rest of the project's rules.

| Setting | Value | Source | Since | Options (default first) |
|---|---|---|---|---|
| **Strictness** (CORE §3) | `<fill>` | `<fill>` | `<date>` | swarm · standard · strict — asked first; sets which tasks run, parallel workers, who merges, review, new tasks, production writes, autopilot, reports |
| Overrides of the preset (row and value) | `<fill>` | `<fill>` | `<date>` | none |
| **Spend level** (CORE §7) | `<fill>` | `<fill>` | `<date>` | **balanced** · lean · thorough — which way model and effort choices lean and when the top rung is used (CORE §7); never removes a check |
| Autopilot and tick (CORE §9) | `<fill>` | `<fill>` | `<date>` | per the strictness: swarm on, a tick every ~30 min · standard, strict off — work on the owner's task or batch command |
| **Work mode** (CORE §4) | `<fill>` | `<fill>` | `<date>` | **by task** — the owner names a task, then the next (solo work) · batch — a batch command runs the recipe below over the tracker (a team, a board) |
| Language: conversation / artifacts | `<fill>` | `<fill>` | `<date>` | owner's language / English |
| Voice in commits and PRs | the owner's | core | — | not a setting: always the owner's, no AI lines (CORE §11) |
| Flake quarantine (CORE §4 *A red check*) | on, confirmed | default | `<date>` | **on, each one confirmed by the owner (a quiz)** · on, without asking · off — never asked at init; changed only through "Coordinator, settings" |
| Who merges | `<fill>` | `<fill>` | `<date>` | per the strictness (CORE §3): swarm the coordinator on green CI + a confirmed verdict · standard the same, the owner for risky changes · strict humans |
| Review gates | `<fill>` | `<fill>` | `<date>` | the verifier always (CORE §6); human review: swarm none · standard the owner on risky changes · strict developer and/or business analyst, their comments back to the same branch + re-review |
| Production and MCP writes (CORE §1.4) | `<fill>` | `<fill>` | `<date>` | per the strictness: swarm, standard write when the task needs it, backup first · strict read-only except named actions |
| Model pins (kinds routing must not change, CORE §7) | `<fill>` | `<fill>` | `<date>` | none — the coordinator routes every kind itself (`coordinator/ROUTING.md`) |
| Usage caps (CORE §9) | `<fill>` | `<fill>` | `<date>` | weekly 90%, short window 95%; over only with permission |
| State repository: remote, branch, private (CORE §12b) | `<fill>` | `<fill>` | `<date>` | solo: the owner's account · team: the team's organization · local only (lost with the disk); branch `state`; always private; pointer in `CLAUDE.md`: yes / no (never in a client's repository) |
| Core (CORE §2) | `<fill>` | `<fill>` | `<date>` | a local copy in `coordinator/core/` at claude-coordinator commit `<sha>`; local edits: `<list or none>` |
| Coordinator name (CORE §2) | `<fill>` | `<fill>` | `<date>` | `<Project> Coordinator` — always containing the English word `Coordinator`; the session is started with `claude --name "<name>"` or renamed with `/rename <name>` |
| Core reports (procedures/CORE-FINDINGS.md) | `<fill>` | `<fill>` | `<date>` | **automatically** · show me each one first (client work) · no — by hand: how the core's own failures reach claude-coordinator |
| Self-improvement summaries (procedures/RETRO.md) | `<fill>` | `<fill>` | `<date>` | **show me first** (the first week always) · send · only me — whether the retro sends its anonymous summary of numbers to claude-coordinator |
| Self-improvement id | `<fill>` | `<fill>` | `<date>` | 12 random hex digits from `scripts/retro --new-id`, made once, never derived from a name |
| Worktree roots | `<fill>` | `<fill>` | `<date>` | none — the workers' worktrees are under `.claude/worktrees`; else every `--worktree-root` the project gives start-worker, relative to the project root where it can be (`../<project>-wt`), split by `,` — the retro counts sessions started there |
| Protected branches (CORE §1.9, TOOLKIT *Safety*) | `<fill>` | `<fill>` | `<date>` | `main` and `master` always, plus the repository's default branch and the branches protected on the code host (INIT 3.1, question 14) — exact names, no patterns, added to main and master, never replacing them; the added ones written to the worker safety file's `env` `COORD_PROTECTED_BRANCHES` and its push deny rules; none: main and master only |
| Last retro (week of) | `<fill>` | `<fill>` | `<date>` | none yet — the retro sets it (procedures/RETRO.md) |
| Last core report | `<fill>` | `<fill>` | `<date>` | none yet — the retro report for the core sets it to its period `<from>..<to>` once filed; the next report starts the day after (procedures/RETRO.md §8) |

## Project
| Question | This project | Default to offer |
|---|---|---|
| Session names | `<fill>` | `#<task> <role>: <title>` (role = worker / verifier; tester and scout run as subagents), `researcher: <topic>`, the coordinator by its name in *Settings*; no project prefix in the others |
| Worker permission mode | `<fill>` | **`auto`** in every preset · `acceptEdits` (cautious) where the owner wants prompts |
| Named production actions (strict) | `<fill>` | none |
| Where the coordinator's files live (`PROJECT.md`, `BINDINGS.md`, `LOG.md`) | `<fill>` | **`coordinator/` as its own local git repository** (state repository, CORE §12b), excluded from the project's git; committed at every change, pushed per CORE §12b |
| Who reviews CI, deployment, migration and release-flag changes (CORE §1.1) | `<fill>` | per the strictness: swarm the verifier · standard the owner · strict a human |
| Project code to other services — web search, third-party tools (CORE §1.13) | `<fill>` | strict: ask · swarm, standard: allowed |
| Standing approvals (CORE §1, Definitions) | `<fill>` | none |
| Product, users; solo or team | `<fill>` | — |
| Current milestone / sprint and what "done" means | `<fill>` | a demo scenario / the sprint's issues |
| Who owns the scope | `<fill>` | solo: the owner · a team or a client: the business analyst / product owner (INIT 3.1, question 3) |

## Sources of truth (procedures/SOURCES.md)
| Kind | Main system | The coordinator may |
|---|---|---|
| Code and review | `<fill>` | read, write through PRs |
| Tasks and statuses | `<fill>` | read, change status |
| Requirements | `<fill>` | read only |
| Decisions and their reasons | `<fill>` | write through the change path |
| Acceptance | `<fill>` | read only |
| Design | `<fill>` | read only |
| The coordinator's memory | the state repository | write |

Other sources: the catalog `coordinator/SOURCES.md`. Missing tools (no tracker, code host or git): `<none or the mode>`.

## Tracking
| Question | This project | Default to offer |
|---|---|---|
| Tracker, board, statuses | `<fill>` | GitHub issues + project board: Backlog / Todo / In Progress / Testing / Done · no tracker: `coordinator/TASKS.md` |
| Hierarchy and labels | `<fill>` | epics → tasks / bugs; `epic` `task` `bug`, `area:*`, `needs-design`, `needs-owner-test` |
| What becomes an issue | `<fill>` | every piece of work |
| Unplanned but needed work | `<fill>` | per the strictness (CORE §3): swarm filed and queued · standard filed, starts on the scope owner's yes · strict proposed only |
| The owner's wishes | `<fill>` | an issue at once, in the owner's words |
| Issue fields | `<fill>` | scope, out of scope, **do not decide**, depends on, acceptance criteria, verification, estimate |
| Progress line | `<fill>` | "milestone ≈ N% (closed/all)" in the report after each merge |

## The batch recipe (CORE §4)
What the batch command runs here (work mode *batch*, and the autopilot's tick) — an ordered recipe, agreed at init,
revised any time. Under *by task* only the approval gate and the comment rows apply.

| Question | This project | Default to offer |
|---|---|---|
| Batch command and recipe (ordered steps) | `<fill>` | "start a new cycle" (or the owner's own words): sync PRs → clean up merged work → collect and triage new comments → plan next work and merge order → approval gate → delegate → report |
| Parallel tasks | `<fill>` | per the strictness: swarm as many as runnable (e.g. 10) · standard 2–3 · strict one |
| Approval gate | `<fill>` | swarm: auto for queued and obvious items, ask for the rest · standard, strict: announce the plan (item → issue/PR → what and why → model) and wait for the owner's approval |
| Obvious review comments | `<fill>` | swarm, standard: fixed automatically · strict: listed in the plan like any other item |
| Stale comments | `<fill>` | flagged with the reason (task changed / comment obsolete); never acted on without the owner |

## Coding standards (CORE §4b)
| Question | This project | Default to offer |
|---|---|---|
| Language / framework / library rules | `<fill>` | established best practice for the stack as short rules (e.g. React: components, hooks, server vs client; TypeScript strict) |
| Architecture rules | `<fill>` | folder structure, data access layer, error handling, naming |
| Where they live | `<fill>` | `docs/standards.md`, linked here; reviewers check against it |

## Research (CORE §4b)
| Question | This project | Default to offer |
|---|---|---|
| Start research | `<fill>` | propose in one line with the model it would use; start only on the owner's yes |
| Where results go | `<fill>` | a catalog document in the project's docs (`docs/research/<topic>.md`) or a table in the coordinator session |
| Radar: references and competitors | `<fill>` | proposed from the init research (similar products, open-source projects, mods); one reference when the owner asks ("radar"), never by itself, a light-model researcher; rows decided by the owner in one batch |
| Expectations checklist | `<fill>` | `docs/expectations.md`; re-audited at each milestone checkpoint |

## The change flow
Walked end to end at init (CORE §3, topic d); revise as the project changes.

| Step | This project | Default to offer |
|---|---|---|
| Branch name | `<fill>` | `<issue>-<type>-<slug>` (e.g. `37-feat-saved-cart`); no project prefix, the repository names the project |
| Commit message | `<fill>` | `type: subject (#<issue>)` (never start with `#`: git drops such lines as comments); body with what and why; types feat / fix / docs / refactor / test / chore |
| How often to commit / push | `<fill>` | a commit + push per finished block |
| PR | `<fill>` | **draft** at the first push; title as the commit (`feat: saved carts per account (#37)`); `Closes #<issue>`; Summary / Test plan (tick only what was run) |
| AI review | `<fill>` | independent reviewer agent per CORE §6; re-review until approval with no Blocker / Major |
| Who marks ready | `<fill>` | the coordinator after approval + green CI; never the author |
| Progress comments | `<fill>` | a short PR comment after each meaningful push |
| Multi-issue PRs | `<fill>` | each issue linked and moved on the board |
| Deploy | `<fill>` | preview per PR; production from the main branch |
| Docs-only changes | `<fill>` | PR without CI; merged first if they change rules |

## Testing and CI
| Question | This project | Default to offer |
|---|---|---|
| Definition-of-done checks per task | `<fill>` | lint + typecheck + build + unit tests (+ DB tests with a migration) |
| End-to-end check of the task | `<fill>` | a headless-browser scenario that clicks through the changed pages on a database seeded with test data |
| CI layout | `<fill>` | a fast set on every PR, heavy checks by path filter, caching; a full suite over about 10 minutes: a fast selection on PRs (the changed paths and the PR's own tests, stopping at the first failure), the full suite once before the merge on the updated head; long scenario tests cut to their asserted moments or moved to a manual set |
| CI time budget | `<fill>` | a change adding more than 30 seconds to the full suite asks the coordinator first; every worker report states it (roles/worker.md) |
| Improvements | `<fill>` | the coordinator proposes checks that save time or owner attention (CORE §4b); the owner decides |

## Voice in artifacts
Always the owner's: first person, no mention of AI, no AI co-author lines (CORE §11).

| Question | This project | Default to offer |
|---|---|---|
| Comment style | `<fill>` | terse bullets |

## Acceptance
| Question | This project | Default to offer |
|---|---|---|
| Who accepts, how | `<fill>` | the owner / QA / business analyst on preview or the real target, one question per item |
| After a requested change | `<fill>` | re-accepted before merging |
| Machine during the test | `<fill>` | quiet: no builds, launches, CI pushes |

## Environments and production
| Question | This project | Default to offer |
|---|---|---|
| Environments | `<fill>` | local · preview (per PR) · production |
| Release path to production | `<fill>` | merge to main → automatic deploy; DB migrations via the CI workflow (swarm, standard: agents may also apply them when a task needs it, backup first) |
| Database changes | `<fill>` | migration files; never edit an applied migration · strict: no dashboard edits, no direct pushes from a dev machine |
| Production backup before an irreversible change *(if any)* | `<fill>` | the command and destination in `BINDINGS.md` (e.g. a database dump / platform snapshot), filled before the first such write |
| Release flags *(if any)* | `<fill>` | features that act on real users or money ship disabled behind an env flag; enabled after merge in a documented order |

## Parallel work and resources
| Question | This project | Default to offer |
|---|---|---|
| Parallel workers allowed | `<fill>` | yes, isolated |
| Per-worker isolation | `<fill>` | working copy + DB stack + ports derived from the task number (BINDINGS) |
| Shared resources to guard | `<fill>` | the main DB stack, a single device, the CI runner |
| Serial identifiers | `<fill>` | migration versions: check main + open PRs + branches, each branch owns its slot |
| Processes after a task pauses | `<fill>` | stop; restart when it continues (keep / cache if start-up is slow) |

## Shared files (CORE §4a)
Files every task may add to; `scripts/merge-queue` takes them as `--shared` globs. Proposed from the
history (the files most of the last weeks' PRs changed) at init or by the one-time step `shared-files`.

| Question | This project | Default to offer |
|---|---|---|
| Append-only docs and lists | `<fill>` | the journal, decisions and traps docs, translation files, a test config's list of suites; a markdown log gets `<file> merge=union` in `.gitattributes` (git keeps both sides' added lines) or becomes a folder with one file per entry |
| Generated files, each with the command that regenerates it | `<fill>` | e.g. database types: `<command>`; never merged by hand |
| The queue's merge method | `<fill>` | squash (merge, where a stack of PRs lands as one merge commit) |
| CI runs of older heads | `<fill>` | cancelled by the CI itself: `concurrency: { group: <workflow>-<ref>, cancel-in-progress: true }` |

## Risk tiers
| Question | This project | Default to offer |
|---|---|---|
| High-risk areas | `<fill>` | money, roles, permissions / RLS, audit, business time, customer data |
| Extra rules there | `<fill>` | stronger model, mandatory review, negative tests, owner told before merge |

## Budget, time and models
| Question | This project | Default to offer |
|---|---|---|
| Leads (CORE §4, roles/lead.md) | `<fill>` | for tasks whose pieces must land together (3+ sub-contracts, more than one worker's context); up to 3 workers per lead, within the preset's parallel workers |
| Spend forecast and report (CORE §7a) | `<fill>` | the block's estimate in cost, limit percent and time in the plan; forecast vs actual in the block report |
| Time estimates | `<fill>` | strict: optimistic / realistic / pessimistic per task (the low end, median and top of `budget.time`, CORE §7a); aim for realistic, warn before pessimistic · swarm, standard: none |
| Time tracking | `<fill>` | strict: a timesheet draft shown to the owner before it is written · swarm, standard: none |

## Client dependencies
| Question | This project | Default to offer |
|---|---|---|
| Access, accounts, approvals the client owes *(if any)* | `<fill>` | a list with owner and date (`docs/dependencies.md`) |

## MCP and integrations
| Technology found | MCP / connector | Rights | Connected? | CLI fallback |
|---|---|---|---|---|
| `<fill>` | `<fill>` | `<read / write>` | `<yes/no>` | `<fill>` |

## Lessons (CORE §10) — one line each, newest last
- `<date>`: `<lesson>`

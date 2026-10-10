# Project rules — <project name>

Layer 2 of the coordinator (see `CORE.md`). Filled through the init quiz with the owner (CORE §3),
revised whenever the owner changes how the project works. Every row: the question, **this project's
answer**, and a default to offer — "non-commercial" (own, hobby) vs "commercial" (client, paid) where
they differ. Work starts only when no `<fill>` is left (CORE §1.12).

## Project
| Question | This project | Default to offer |
|---|---|---|
| **Commercial or non-commercial** | `<fill>` | — asked first |
| **Swarm or sequential** (many parallel sessions vs logical steps with checks) | `<fill>` | commercial: sequential · non-commercial: swarm |
| Session names | `<fill>` | workers `<KEY>-<task> <title>`, coordinator `<Project> Coordinator`, reviewers `<KEY>-<task> review`, researchers `research: <topic>` |
| Autopilot and periodic tick | `<fill>` | **off** (default) · on only for non-commercial swarm work, by the owner's choice |
| **Autonomy level** (CORE §3) | `<fill>` | **autonomous** — workers in auto mode, routine risky work and production writes when needed (backup first), report everything · cautious — `acceptEdits`, production read-only |
| Production actions | `<fill>` | autonomous: whatever the task needs, backup before irreversible · cautious: only named actions |
| Where the coordinator's files live (`PROJECT.md`, `BINDINGS.md`, `LOG.md`) | `<fill>` | client work: a local folder outside the repository or gitignored · own project: `coordinator/` in the repository |
| Voice; AI co-author line in commits | `<fill>` | client work: the owner's voice, first person, no mention of AI (owner's recorded decision; co-author line removed) · own: no matter |
| Standing approvals (CORE §1, Definitions) | `<fill>` | none |
| Product, users; solo or team | `<fill>` | — |
| Current milestone / sprint and what "done" means | `<fill>` | a demo scenario / the sprint's issues |
| Who owns the scope | `<fill>` | own: the owner · client: the business analyst / product owner |
| Owner's language / artifacts' language | `<fill>` | owner's language / English |
| Decision log, open questions | `<fill>` | `docs/decisions.md`, `docs/open-questions.md` |

## Tracking
| Question | This project | Default to offer |
|---|---|---|
| Tracker, board, statuses | `<fill>` | GitHub issues + project board: Backlog / Todo / In Progress / Testing / Done |
| Hierarchy and labels | `<fill>` | epics → tasks / bugs; `epic` `task` `bug`, `area:*`, `needs-design`, `needs-owner-test` |
| What becomes an issue | `<fill>` | every piece of work |
| Unplanned but needed work | `<fill>` | own: file an issue and do it · client: file an issue and tell the scope owner first |
| The owner's wishes | `<fill>` | an issue at once, in the owner's words |
| Issue fields | `<fill>` | scope, out of scope, **do not decide**, depends on, acceptance criteria, verification, estimate |
| Status page / progress line | `<fill>` | a pinned issue; "milestone ≈ N% (closed/all)" after each merge |

## The cycle (CORE §4)
What "start a new cycle" runs here — an ordered recipe, agreed at init, revised any time.

| Question | This project | Default to offer |
|---|---|---|
| Recipe (ordered steps) | `<fill>` | sync PRs → clean up merged work → collect and triage new comments → plan next work and merge order → approval gate → delegate → report |
| Parallel tasks per cycle | `<fill>` | own, rush: as many as runnable (e.g. 10) · client: a few |
| Approval gate | `<fill>` | own, rush: auto for obvious items, ask for the rest · client: announce the plan (item → issue/PR → what and why → model) and wait for the owner's approval |
| Obvious review comments | `<fill>` | own: fixed automatically · client: listed in the plan like any other item |
| Stale comments | `<fill>` | flagged with the reason (task changed / comment obsolete); never acted on without the owner |
| Periodic tick | `<fill>` | own, autopilot: every ~30 min · client: only on the owner's "start a new cycle" |

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
| Reference sources | `<fill>` | similar open-source projects, libraries, official docs |

## The change flow
Walked end to end at init (CORE §3, topic d); revise as the project changes.

| Step | This project | Default to offer |
|---|---|---|
| Branch name | `<fill>` | `<issue>-<slug>` (client) · `KEY-<issue>-<type>-<slug>` (own) |
| Commit message | `<fill>` | `[KEY-<issue>]: type(scope): subject` or `KEY-<issue> type: subject`; body with what and why; types feat / fix / docs / refactor / test / chore |
| How often to commit / push | `<fill>` | a commit + push per finished block |
| PR | `<fill>` | **draft** at the first push; title as the commit; `Closes #<issue>`; Summary / Test plan (tick only what was run) |
| AI review | `<fill>` | independent reviewer agent per CORE §6; re-review until approval with no Blocker / Major |
| Who marks ready | `<fill>` | the coordinator after approval + green CI; never the author |
| Human review | `<fill>` | own: none · client: developer and/or business analyst; their comments go back to the same branch + re-review |
| Who merges | `<fill>` | own, rush: the coordinator / worker on green CI + approval · client: humans (the owner stays in the process) |
| Progress comments | `<fill>` | a short PR comment after each meaningful push |
| Multi-issue PRs | `<fill>` | each issue linked and moved on the board |
| Deploy | `<fill>` | preview per PR; production from the main branch |
| Docs-only changes | `<fill>` | PR without CI; merged first if they change rules |

## Testing and CI
| Question | This project | Default to offer |
|---|---|---|
| Definition-of-done checks per task | `<fill>` | lint + typecheck + build + unit tests (+ DB tests with a migration) |
| End-to-end check of the task | `<fill>` | a headless-browser scenario that clicks through the changed pages on a database seeded with test data |
| CI layout | `<fill>` | a fast set on every PR, heavy checks by path filter, caching |
| Improvements | `<fill>` | the coordinator proposes checks that save time or owner attention (CORE §4b); the owner decides |

## Voice in artifacts
| Question | This project | Default to offer |
|---|---|---|
| Whose voice in commits, PR and issue comments | `<fill>` | client: the owner's, first person, no mention of AI · own: no matter |
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
| Release path to production | `<fill>` | merge to main → automatic deploy; DB migrations via the CI workflow (autonomous: agents may also apply them when a task needs it, backup first) |
| Database changes | `<fill>` | migration files; never edit an applied migration · cautious level: no dashboard edits, no direct pushes from a dev machine |
| Production backup before an irreversible change | `<fill>` | the command and destination in `BINDINGS.md` (e.g. a database dump / platform snapshot), filled before the first such write |
| Release flags | `<fill>` | features that act on real users or money ship disabled behind an env flag; enabled after merge in a documented order |
| Production rights of tools / MCP | `<fill>` | per the autonomy level (autonomous: write when the task needs it, backup first) |

## Parallel work and resources
| Question | This project | Default to offer |
|---|---|---|
| Parallel workers allowed | `<fill>` | yes, isolated |
| Per-worker isolation | `<fill>` | working copy + DB stack + ports derived from the task number (BINDINGS) |
| Shared resources to guard | `<fill>` | the main DB stack, a single device, the CI runner |
| Serial identifiers | `<fill>` | migration versions: check main + open PRs + branches, each branch owns its slot |
| Processes after a task pauses | `<fill>` | stop; restart when it continues (keep / cache if start-up is slow) |

## Risk tiers
| Question | This project | Default to offer |
|---|---|---|
| High-risk areas | `<fill>` | money, roles, permissions / RLS, audit, business time, customer data |
| Extra rules there | `<fill>` | stronger model, mandatory review, negative tests, owner told before merge |

## Budget, time and models
| Question | This project | Default to offer |
|---|---|---|
| Usage caps | `<fill>` | weekly 90%, short window 95%; over only with permission |
| Models available | `<fill>` | Fable (own limit), Opus, Sonnet, Haiku |
| Time estimates | `<fill>` | client: optimistic / realistic / pessimistic per task; aim for realistic, warn before pessimistic |
| Time tracking | `<fill>` | client: a timesheet draft shown to the owner before it is written |

## Client dependencies
| Question | This project | Default to offer |
|---|---|---|
| Access, accounts, approvals the client owes | `<fill>` | a list with owner and date (`docs/dependencies.md`) |

## MCP and integrations
| Technology found | MCP / connector | Rights | Connected? | CLI fallback |
|---|---|---|---|---|
| `<fill>` | `<fill>` | `<read / write>` | `<yes/no>` | `<fill>` |

## Lessons (CORE §10) — one line each, newest last
- `<date>`: `<lesson>`

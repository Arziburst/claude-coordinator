# Project rules — example: a client web app (Next.js + Supabase)

A generic, filled example of layer 2 for client work: a web app built for a client, a
small team with a human business analyst, Vercel hosting, Supabase database. Names are illustrative.

## Project
| Question | This project |
|---|---|
| Commercial or not | **commercial** (client work) — strict defaults |
| Swarm or sequential | **sequential**: one or two tasks at a time, each reviewed and accepted before the next |
| Autonomy level | **autonomous**: workers in auto mode merge main, resolve conflicts, rebase, write to their local stacks and to production when a task needs it (backup first), and report |
| Autopilot, tick | off, no tick (cycles on the owner's word) |
| Core | local copy in the state repository (`core/`), editable for this project; "update the core" on command |
| Coordinator's files | outside the client repository, in a clone of the private state repository |
| Session names | `APP-<issue> <title>`, coordinator `App Coordinator` |
| Product; team | a web app for a client's customers; the owner (developer) + a business analyst + a supervising developer |
| Milestone / sprint | the current sprint's issues on the board |
| Scope owner | the business analyst |
| Languages | owner: Russian; artifacts: English |
| Decision log, open questions | `docs/decision-log.md`, `docs/open-questions.md` — business values only from there, else `TBD` |

## Tracking
| Question | This project |
|---|---|
| Tracker | GitHub issues + project board: Backlog / Todo / In Progress / Testing/QA / Done (moved by field ids, never by labels) |
| What becomes an issue | every piece of work |
| Unplanned but needed work | file an issue, tell the business analyst, take it only once it is in the sprint |
| Issue fields | epic, depends on, estimate, read first, scope, out of scope, **do not decide**, constraints, acceptance criteria, verification |

## The cycle — on the owner's "start a new cycle" only
1. Sync: which PRs merged, which are open, their checks.
2. Clean up merged and fully pushed work: stop its Supabase stack (`docker` containers), stop its dev
   servers, remove its worktree. Unfinished work untouched; anything unclean reported.
3. Collect new comments on open PRs (business analyst, reviewers, CI) and triage: valid / needs the owner /
   stale (the task changed or the comment is long forgotten — say why) / out of scope.
4. Plan: fixes and next sprint tasks, order, merge order.
5. **Announce and wait:** send the owner "ready to hand out: item → issue / PR → what and why → model";
   delegate only what the owner approves.
6. Delegate → review → mark ready → report.

## Research
Before a new kind of feature (payments, scheduling, auth flows …) the coordinator proposes a short
research: libraries, Supabase / Next.js patterns, how others built it. Result: a table in the
coordinator session (or `docs/research/<topic>.md` when the team should read it); the owner picks.

## The change flow
| Step | This project |
|---|---|
| Branch | `<issue>-<slug>` (multi-issue `<n1>-<n2>-<slug>`) |
| Commit | `[APP-<n>]: type(scope): imperative lowercase subject` (≤ 72 chars), detailed body; never amend a pushed commit |
| Commit / push | a commit + push per finished block |
| PR | **draft** at the first push; title with the same prefix; `Closes #` / `Refs #`; Summary / Blocks / Test plan (tick only what was run); claimed migration slot in the body |
| AI review | reviewer agent per CORE §6, re-review until approval with no Blocker / Major |
| Ready | the coordinator runs `gh pr ready` after approval + green CI; the author never does |
| Human review | the business analyst (scope, acceptance); fixes on the same branch + re-review |
| Merge | humans only (the business analyst / the owner) |
| Deploy | Vercel preview per PR (behind SSO); production on merge to `main` |
| Cleanup | after merge: stop the task's DB stack, remove the worktree only if clean and pushed |

## Testing and CI
| Question | This project |
|---|---|
| Per task | lint + typecheck + build + unit tests; with a migration `db:reset` + pgTAP |
| End-to-end | after a task, a headless Chrome scenario clicks through the changed pages on the worker's local stack seeded with test data; on the PR, a Playwright smoke run against the Vercel preview |
| CI | migrations check, lint, typecheck, unit, build, DB reset + pgTAP on every PR; a production-migrations dry run |

## Voice
Commits, PR and issue comments in the owner's voice, first person, terse bullets, **no mention of AI**.

## Environments and production
| Question | This project |
|---|---|
| Environments | local (per-worktree Supabase stack) · Vercel preview · production |
| Release path | merge → Vercel deploy; DB migrations via a manual CI workflow with `confirm=apply` — or applied by a worker when a task needs it, dump first |
| Database | migration files; never edit an applied migration; production data fixes when a task needs them, dump first, logged |
| Release flags | jobs that charge customers ship off; enabled by an env flag set exactly to `true` + redeploy, in the documented order |
| Production rights of tools / MCP | autonomous: the Supabase MCP / CLI may write to production when a task needs it — a dump or snapshot first for schema and bulk data changes, every write logged; the connector's tools are listed at init. The candidate denies in `settings.json` (this folder) are for a cautious project |

## Parallel work and resources
| Question | This project |
|---|---|
| Isolation | worktree `<issue>-<slug>`, Supabase stack `app-<issue>`, ports `54000 + (<issue> mod 100) * 10` (API, DB, Studio …) |
| Shared resources | `app-main` stack mirrors `main` — never reset from a worktree (guarded by an npm pre-script) |
| Serial identifiers | migration timestamps: check `main`, open PRs, unmerged branches, remote history; each branch owns its slot |
| Processes | stop the task's stack when the task pauses; restart on resume; stale stacks cleaned after 7 days |

## Risk tiers
Money, roles, business time, audit, RLS: stronger model, RLS checklist, negative tests (pgTAP), the owner
told before merge.

## Budget and time
| Question | This project |
|---|---|
| Estimates | optimistic / realistic / pessimistic per task (client-approved); aim for realistic, warn before pessimistic |
| Time tracking | a timesheet draft shown to the owner before it is written |
| Models | Opus for product work, Opus high for money / RLS, Sonnet for docs and reviews of small changes |

## Client dependencies
`docs/dependencies-access.md`: credentials, accounts, approvals the client owes — owner and date each.

## MCP and integrations
| Technology | MCP | Rights | CLI fallback |
|---|---|---|---|
| GitHub | GitHub MCP / `gh` | write (issues, PRs) | `gh` |
| Supabase | Supabase MCP | write when a task needs it (backup first); local stack per worktree | `supabase` CLI |
| Vercel | Vercel MCP | read (deployments, logs) | `vercel` CLI |
| Browser | Playwright | preview smoke tests | `npx playwright` |

## Lessons (examples)
- Take only sprint tasks; file anything unplanned and tell the business analyst first.
- Reviewers check the PR title prefix — it is easy to miss.
- A green smoke check can mean "skipped" — treat a skipped check as a gap.

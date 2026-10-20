# Bindings — <project name>

Layer 3 of the coordinator (see `CORE.md`): the concrete tools behind the generic terms. Kept current by
the coordinator.

Rows marked "(re-detect)" differ per machine: check them at every start on a new machine.

| Generic term | Here |
|---|---|
| Operating system(s) and shells | `<Windows / macOS / Linux; PowerShell / bash / zsh>` — commands below are for these; per-OS variants where machines differ |
| Core scripts (hook, start-worker, status line) | `<absolute path to coordinator/core/scripts>` (re-detect) |
| Repository, main branch, protected branches | `<fill>` |
| State repository (private) | `<url or local only>` |
| Owner's working copy | `<path>` |
| Build / run / test / lint / typecheck commands | `<fill>` |
| Definition-of-done checks | `<fill>` |
| Start a worker (with its session name, model, effort, working copy, report address `--report-to`) | `<command>` |
| Start a worker without the wrapper (fallback, UPDATE-CORE step 3) | `<the core start-worker command with this project's flags>`; the brief as the wrapper builds it: `roles/worker.md`, the contract, the report address and phrase |
| Coordination scripts (the project's own wrappers around the core; `check-scripts` runs on them, CORE §12a) | `<folders, or none>` |
| Models — the ladder (CORE §7) (re-detect) | light `<id>` · strong `<id>` · top `<id>` or none; Fable on the plan — the owner's answers, asked at init and on a plan change (one-time step `fable-on-plan`): `/usage` shows a *Current week (Fable)* row `<yes / no>`, usage credits `<on / off>`, `<date>` (no row → Fable is off the ladder whatever a probe says; it shares the 5-hour and weekly limits, burns them faster, up to 50% of the week on Fable); off the ladder until the weekly reset after a Fable limit or credits message `<date, or none>`; list prices per million tokens (input / output / cache read / cache write at the 1-hour price, TOOLKIT *Usage*) `<fill>`, also as the prices file `scripts/run-stats --limits` reads (one line per model, `<id> $5 / $25 / $0.50 / $10`, `top` after the top rung's model when it is above the strong one, i.e. Fable; `not-weekly` only for a model with a limit of its own outside the weekly one — none known, never Fable) `coordinator/prices.txt` (one-time step `prices-file`; a model whose price is not on the pricing page: asked from the owner); probed `<date>` (the cheap probe, TOOLKIT *Usage*), login method and `subscriptionType` `<from claude auth status>` |
| Start a reviewer | `<command>` |
| List / stop / remove workers | `<commands>` |
| Worker working copies | `<create / remove commands>` |
| Production backup before an irreversible change (CORE §1.4) | `<command>` → `<destination>`, kept `<how long>` |
| Per-task resources | working copy `<pattern>` · DB stack `<pattern>` · ports `<base> + <task> mod <range>` |
| Start / stop a task's environment | `<commands>` |
| Shared resources and their guards | `<fill>` |
| Move a task on the board | `<command / field ids>` |
| Usage / limits source | `<file or command>` |
| Periodic tick | `<how to create it>` |
| Owner's test station / preview | `<command or URL pattern>` |
| Owner's build (latest product for the owner) | `<command>` |
| Claude permission rules and hooks | `<path>`: deny-list, hooks |

## Project map (CORE §4c)
| What | Where |
|---|---|
| Repositories | `<fill>` |
| Tracker / board | `<fill>` |
| Docs, decision log, open questions | `<fill>` |
| Environments and URLs (local, preview, staging, production) | `<fill>` |
| CI, deployments, logs, dashboards | `<fill>` |
| Design files | `<fill>` |
| **Sensitive data — names and locations only, never values** | `<env files, secret stores, production DB, customer data>` |
| Never touch | `<fill>` |

## Access list (CORE §4c)
| Resource | Needed for | Right | Connected via | Status |
|---|---|---|---|---|
| `<code host>` | `<issues, PRs>` | `<read/write>` | `<CLI / MCP>` | `<connected / to connect>` |
| `<design tool>` | `<design tasks>` | read | `<MCP>` | `<…>` |

## Project-only rules
- `<rule>`

## Traps
- `<trap>`

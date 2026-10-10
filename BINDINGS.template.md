# Bindings — <project name>

Layer 3 of the coordinator (see `CORE.md`): the concrete tools behind the generic terms. Kept current by
the coordinator.

| Generic term | Here |
|---|---|
| Operating system(s) and shells | `<Windows / macOS / Linux; PowerShell / bash / zsh>` — commands below are for these; per-OS variants where machines differ |
| Repository, main branch, protected branches | `<fill>` |
| Owner's working copy | `<path>` |
| Build / run / test / lint / typecheck commands | `<fill>` |
| Definition-of-done checks | `<fill>` |
| Start a worker (with its session name, model, effort, working copy) | `<command>` |
| Start a reviewer | `<command>` |
| List / stop / remove workers | `<commands>` |
| Worker working copies | `<create / remove commands>` |
| Per-task resources | working copy `<pattern>` · DB stack `<pattern>` · ports `<base> + <task> mod <range>` |
| Start / stop a task's environment | `<commands>` |
| Shared resources and their guards | `<fill>` |
| Move a task on the board | `<command / field ids>` |
| Status page | `<link>` |
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

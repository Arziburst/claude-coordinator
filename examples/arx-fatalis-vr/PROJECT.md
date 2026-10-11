# Project rules — Arx Fatalis VR

Filled example of layer 2 (the live copy is in the project: `docs/vr/COORDINATOR.md`, Part B).

## Project
| Question | This project |
|---|---|
| Commercial or not | **non-commercial** (own project, free app) — rush defaults |
| Swarm or sequential | **swarm**: as many parallel workers as the limits allow (often ~10–16) |
| Autopilot, tick, worker mode | on — tick every ~30 min (the owner's choice); workers in bypass mode on the owner's own machine (a deliberate exception, not a default) |
| Core | local and adapted: the project's own playbook (`docs/vr/COORDINATOR.md`, Part A) |
| Coordinator's files | in the repository (`docs/vr/COORDINATOR.md`) |
| Session names | `#<issue> <role>: <title>` (role = worker / verifier / tester; set by `start-worker.ps1`), coordinator `Coordinator` |
| Product, audience | a free VR port of Arx Fatalis (Arx Libertatis engine, OpenXR/SteamVR, Valve Index) as a standalone Steam app requiring the original game |
| Current milestone | **M1 MVP** — the MVP demo scenario (docs/vr/MVP.md) |
| Languages | owner: Russian; artifacts: English |

## Tracking
| Question | This project |
|---|---|
| Tracker | GitHub issues of `Arziburst/arx-fatalis-vr`, board "Arx Fatalis VR" (projects/3) |
| Statuses | Backlog / Todo / In Progress / Testing / Done |
| Hierarchy and labels | epics → sub-issue tasks/bugs; `epic` `task` `bug`, `area:*`, `lane:vr`, `needs-vr-test`, `needs-design`, `model:fable` |
| What becomes an issue | every piece of work; research is always a task |
| The owner's wishes | an issue at once, in the owner's words, listed in the report |
| Status page | pinned issue #193 |
| Progress line | "MVP ≈ N% (closed/all M1 tasks)" after each merge |

## The cycle — on "start a new cycle" and every ~30 min (autopilot, rush)
1. Sync: limits, merged / open PRs, CI, running workers.
2. Clean up merged workers (stop, remove the session, remove the worktree and build folders).
3. Collect worker reports, PR feedback, the owner's headset verdicts; triage.
4. Plan: which tasks can start now, in what order to build and to merge (merge queue), as many in
   parallel as the limits allow (often ~10).
5. Approval gate: **auto** — start the runnable tasks at once; only product-experience questions go to
   the owner ahead of time.
6. Delegate → review → headset batch when ready → merge queue → report with the progress line.

## Research
Reference VR mods and ports (OpenMW VR, Skyrim VR mods, Valheim VR, Doom 3 BFG VR …) studied one per
block by a Sonnet researcher; findings in `docs/vr/RESEARCH-reference-mods.md` (rows F-1…); the owner
reviews one table per block (take / not / after MVP), taken rows become tasks.

## Changes
| Question | This project |
|---|---|
| Branch | `ARXVR-<issue>-<type>-<short-name>` |
| Commit | `ARXVR-<issue> <type>: <description>`, body `Refs #<issue>` |
| Pull request | title as the commit; `Closes #<issue>`, What / How verified / How to test |
| Every change a PR? | yes; docs-only PRs have no CI |
| Progress comments | after each meaningful push |

## Review and integration
| Question | This project |
|---|---|
| Reviewer | reviewer agent (Sonnet medium) for engine core, render, input, the VR frame path, shared scripts; the coordinator reads docs/test/small tooling PRs itself |
| Who merges | the worker on fully green CI + PASS; `needs-vr-test` only after the owner's headset verdict |
| Many open PRs | merge queue, one at a time (red-main fix → rule changes → dependencies → rest); accepted PRs get the single CI runner first |

## Acceptance
| Question | This project |
|---|---|
| How | the owner's headset test, batched, one question per PR, via the test station with known saves |
| After a requested change | re-tested in the headset before merging |
| Machine during the test | quiet: no builds, launches, CI pushes; performance log on |
| Combat/magic tests | in the test playground once it exists |

## Budget and models
| Question | This project |
|---|---|
| Caps | weekly 90%, 5-hour 95% |
| Models | Fable xhigh (heaviest), Opus high/medium (engine), Sonnet medium (docs, tests, tooling, research, reviews) |

## MCP and integrations
| Technology | MCP / connector | Connected |
|---|---|---|
| GitHub | `gh` CLI (REST; GraphQL only for the board) | yes |

## Lessons (examples)
- 2026-10-10: never tell a worker to merge over a red or pending check, even a known flake.
- 2026-10-10: serialise merges — parallel merges thrash on shared doc tables.
- 2026-10-10: workers never poll CI in loops — many sessions trip the host's rate limit.
- 2026-10-10: a change requested in a headset test is re-tested before merging.

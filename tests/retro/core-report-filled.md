<!-- core retro report, format 1 -->
**Retro report for the core.** How one project used the core since its last report: numbers made by the core's retro script and short anonymous lines; no names, paths, links, code, file names or task text leave the project.

## Report
| Field | Value |
|---|---|
| project | 3f9a0c1b7e42 |
| period | 2026-09-21..2026-10-29 |
| core commits | 1ebe968, 7c2d4a9 |
| format | 1 |

## Profile
| Field | Value |
|---|---|
| stack class | web |
| solo or team | solo |
| strictness | standard |
| spend level | balanced |
| work mode | by task |
| os | windows |

## Five axes
| Axis | Measure | Period |
|---|---|---|
| cost | tasks | 4 |
| cost | merged | 3 |
| cost | median_per_task | 3.53 |
| cost | total | 15.65 |
| cost | coordinator | 3.00 |
| cost | per_merged_task | 5.22 |
| speed | ready_median | 50 |
| speed | work_median | 31 |
| speed | owner_wait_median | 20 |
| speed | owner_wait_open | 1 |
| quality | rework_rate | 25% |
| quality | escalated_rate | 25% |
| quality | failed_rate | 25% |
| quality | escapes | 1 |
| quality | escapes_per_10_merged | 3.3 |
| predictability | cost_forecasts | 4 |
| predictability | cost_logged | 4 |
| predictability | cost_rebuilt | 0 |
| predictability | cost_in_range | 25% |
| predictability | cost_ratio_median | 185% |
| predictability | work_forecasts | 0 |
| predictability | work_logged | 0 |
| predictability | work_rebuilt | 0 |
| predictability | work_in_range | — |
| predictability | work_ratio_median | — |
| predictability | ready_forecasts | 0 |
| predictability | ready_in_range | — |
| predictability | ready_ratio_median | — |
| stability | failed_runs | 1 |
| stability | guard_blocks | — |
| stability | deny_rule_blocks | — |
| stability | guard_around | — |
| stability | guard_false_positives | 2 |
| stability | guard_errors | — |
| stability | refusals | — |
| stability | tool_errors | — |
| stability | tool_calls | — |
| stability | tool_error_rate | — |
| stability | cache_rewrites | — |
| stability | cache_rewrites_per_task | — |
| stability | waiting_minutes | — |
| stability | rereads | — |

— too little data: under 3 tasks, merged tasks or forecasts, under 100 tool calls, or no transcripts, journal or escapes file.

## Runs by role
| Role | Runs |
|---|---|
| coordinator | 1 |
| lead | 1 |
| worker | 7 |
| tester | 2 |
| verifier | 3 |
| scout | 1 |
| researcher | 1 |
| other | 0 |

## Guard and refusals
| Guard reason | Blocks | Retried | Around | Changed | Stopped |
|---|---|---|---|---|---|

| Refusal | Count | Retried | Around | Changed | Stopped |
|---|---|---|---|---|---|

## Core findings
| Status | Findings |
|---|---|
| new | 1 |
| sent | 2 |
| discussed | 1 |
| fixed | 2 |
| dropped | 1 |
| not core | 1 |
| local core edits | 2 |

## Features
| Feature | Used | How often | Trusted | Decision changed | Friction |
|---|---|---|---|---|---|
| F-START-01 | yes | every session | yes | none | none |
| F-WORK-04 | yes | every task | yes | a task was split in two before it started | the contract check was strict but fair, and a missing criterion was caught twice before a worker started, which saved a round of rework on two of the hard tasks |
| F-WORKERS-01 | yes | every task | yes | a big brief went through a file | the start-worker.sh flags are many to remember |
| F-SAFETY-02 | yes | weekly | no | none | two false positives on a release push, see CORE.md on protected branches |

## Helped and hindered
| Rank | Helped most | Got in the way most |
|---|---|---|
| 1 | tests written before the worker | false positives of the guard |
| 2 | the merge queue | long briefs |
| 3 | the weekly numbers | none |

## Proposals
| Proposal |
|---|
| let the guard name the protected branch it saw |

Data for the core's retro, not a bug report: the maintainer acts on it only after the owner's discussion and yes.

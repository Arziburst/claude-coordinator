# Features — fixture

A small map for the core report's test: four features, their ids in the summary and as blocks.

## Summary

| ID | Feature | In one line | Group |
|---|---|---|---|
| F-START-01 | The one start sequence | every session runs the same steps and then waits | START |
| F-WORK-04 | Contracts | every delegated task is a contract with criteria and checks | WORK |
| F-WORKERS-01 | start-worker | a named background session in its own worktree | WORKERS |
| F-SAFETY-02 | The guard | a hook that blocks the dangerous commands | SAFETY |

## START

### F-START-01 The one start sequence
- defined: CORE.md §2
- entry: any fresh session
- promises: the steps run in order
- tested by: none
- not covered: no automated check

## WORK

### F-WORK-04 Contracts
- defined: CORE.md §4
- entry: a delegated task
- promises: every contract has criteria and checks
- tested by: tests/check-contract/
- not covered: none

## WORKERS

### F-WORKERS-01 start-worker
- defined: scripts/start-worker.sh
- entry: the coordinator starts a worker
- promises: a worktree and a named session
- tested by: tests/start-worker/
- not covered: none

## SAFETY

### F-SAFETY-02 The guard
- defined: scripts/guard.sh
- entry: every tool call of a worker
- promises: a push to a protected branch is blocked
- tested by: tests/guard/
- not covered: none

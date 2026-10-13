---
id: t1
title: An oracle criterion whose text says "how:"
intent: >
  The criterion's own text holds "how:"; it still has no how key, so the oracle names no check.
acceptance:
  - criterion: explain how: the sync works
    check: oracle
  - criterion: the sync runs twice without a change
    check: oracle
    how: tests/sync.sh twice, the second run prints "no change"
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
touches: [sync.sh]
---

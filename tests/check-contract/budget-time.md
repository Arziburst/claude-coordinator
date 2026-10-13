---
id: t7
title: A time estimate in words
intent: >
  budget.time is optional, but when it is there it is minutes or a range of minutes: words warn.
acceptance:
  - criterion: the list is sorted
    check: oracle
    how: tests/sort.sh passes
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
  time: about an hour              # minutes, not words
touches: [sort.sh]
---

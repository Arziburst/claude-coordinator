---
id: t4
title: criterion is not the first key of its items
intent: >
  Items led by check: hold criteria that the check would otherwise not see at all.
acceptance:
  - check: oracle
    criterion: a.txt holds "a"
    how: cat a.txt prints a
  - check: review
    criterion: the code reads well
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
touches: [a.txt]
---

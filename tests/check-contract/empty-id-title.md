---
id:
title: ""            # a title in name only
intent: >
  An empty id and an empty title are errors, as an empty intent is.
acceptance:
  - criterion: a.txt holds "a"
    check: oracle
    how: cat a.txt prints a
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

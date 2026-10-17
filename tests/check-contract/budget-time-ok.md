---
id: t8
title: A time estimate as minutes and as a range with blanks
intent: >
  budget.time in whole or decimal minutes, alone or as a range, passes without a warning.
acceptance:
  - criterion: the list is sorted
    check: oracle
    how: tests/sort.sh passes
tests_first: yes
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
  time: 12.5 - 40                  # minutes
touches: [sort.sh]
---

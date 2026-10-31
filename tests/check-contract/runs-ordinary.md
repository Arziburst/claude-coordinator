---
id: t9
title: A budget inside the run log's range
intent: >
  The run log's line for ordinary / opus has the cost 6 and the time 40 inside its range (runs.tsv).
kind: ordinary
acceptance:
  - criterion: the list is sorted
    check: oracle
    how: tests/sort.sh passes
tests_first: yes
non_goals:
  - no changes beyond this contract's acceptance, its diagnostics and its tests
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: opus
  escalate_to: fable
  cost: 6
  time: 40
touches: [sort.sh]
---

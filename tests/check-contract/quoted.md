---
id: "t2"
title: 'Quoted values'
intent: >
  Quoted values read like plain ones, in block items and in flow items.
acceptance:
  - criterion: "the list is sorted"
    check: "oracle"
    how: 'tests/sort.sh passes'
  - criterion: the code reads well
    check: 'review'
  - { criterion: the owner likes the colours, check: "owner" }
  - { criterion: "the empty list prints nothing", check: 'oracle', how: "tests/empty.sh passes" }
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
  time: "18-40"                    # a quoted range of minutes is a range
touches: [sort.sh]
---

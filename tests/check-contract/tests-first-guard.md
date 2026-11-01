---
id: t10
title: Sort the list in place
intent: >
  The list is sorted where it lies, without a copy; the order of equal items
  stays as it was.
inputs:
  - the payment log is not read (inputs are not looked at)
acceptance:
  - criterion: the list is sorted
    check: oracle
    how: tests/sort.sh passes
tests_first: no - tests/sort.sh exists and checks it
non_goals:
  - no changes beyond this contract's acceptance, its diagnostics and its tests
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
touches: [scripts/sort.sh, tests/sort.sh]
---
The body is not part of the contract: a customer, a role or a refund named here warns of nothing.

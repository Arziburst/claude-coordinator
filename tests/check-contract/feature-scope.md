---
id: t9
title: A feature contract with a scope-neutral default
intent: >
  A new page, not a fix: the scope non-goal names the task's scope instead of "the fix" and passes.
acceptance:
  - criterion: the cart page lists the items
    check: oracle
    how: tests/cart.sh passes
tests_first: yes
non_goals:
  - no changes beyond the task's scope and its tests
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
touches: [cart.sh]
---

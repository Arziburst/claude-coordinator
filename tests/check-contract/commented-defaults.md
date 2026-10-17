---
id: t6
title: Default non-goals commented out
intent: >
  Both default lines are there, but commented out, so neither counts. No budget and no footprint: the
  warnings name CORE sections, so the section sign must come out intact.
acceptance:
  - criterion: the sync runs twice without a change
    check: oracle
    how: tests/sync.sh twice, the second run prints "no change"
tests_first: yes
non_goals:
  # - no changes beyond the fix, its diagnostics and its test
  - keep the old flag # do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
---

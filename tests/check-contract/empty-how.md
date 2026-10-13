---
id: t5
title: A how that names nothing
intent: >
  Every oracle criterion has a how key, but only the last one names a check.
acceptance:
  - criterion: the build is green
    check: oracle
    how: ""
  - criterion: the tests pass
    check: oracle
    how: "   "
  - criterion: the lint is clean
    check: oracle
    how: ~
  - criterion: the docs build
    check: oracle
    how: >
  - { criterion: "explain how: the cache works", check: oracle, how: "" }
  - criterion: the release notes list every change
    check: oracle
    how: >
      scripts/notes.sh lists every merged PR
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  escalate_to: sonnet
  cost: 0.1
touches: [build.sh]
---

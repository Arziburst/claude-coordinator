---
id: st1
title: Self-test - two files
intent: >
  Prove that a lead, its workers and a verifier run on this machine: two small changes land
  together on one integration branch and are merged locally.
inputs:
  - README.md
outputs:
  - the integration branch st1-selftest, merged locally into main by the coordinator
acceptance:
  - criterion: a.txt holds the single line "a"
    check: oracle
    how: git show st1-selftest:a.txt prints a
  - criterion: b.txt holds the single line "b"
    check: oracle
    how: git show st1-selftest:b.txt prints b
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  effort: low
  escalate_to: sonnet
  cost: 2
touches: [a.txt, b.txt]
---
A throwaway sandbox (procedures/SELFTEST.md): no PRs, no code host. Split into st1.1 (a.txt) and
st1.2 (b.txt), one worker each, branches from st1-selftest; merge each into st1-selftest after the
verifier approves; end with the report phrase "selftest st1 done".

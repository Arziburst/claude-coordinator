---
id: st1
title: Self-test - two files
intent: >
  Prove that a lead, its workers and a verifier run on this machine: two small changes land
  together on one integration branch, which the coordinator merges into the test's base.
inputs:
  - README.md
outputs:
  - the integration branch selftest/<c>/st1, merged by the coordinator into selftest/<c>/base
acceptance:
  - criterion: a.txt holds the single line "a"
    check: oracle
    how: git show selftest/<c>/st1:a.txt prints a
  - criterion: b.txt holds the single line "b"
    check: oracle
    how: git show selftest/<c>/st1:b.txt prints b
non_goals:
  - no changes beyond this contract's acceptance, its diagnostics and its tests
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide: []
budget:
  model: haiku
  effort: low
  escalate_to: sonnet
  cost: 0.1                        # below any real plan on purpose: the lead must stop and ask (SELFTEST)
touches: [a.txt, b.txt]
---
The coordinator's self-test (procedures/SELFTEST.md); <c> is the core commit under test, filled in by
the coordinator. No PR inside the block. Split into st1.1 (a.txt) and st1.2 (b.txt), one worker each,
branches selftest/<c>/st1.<n> from selftest/<c>/st1; merge each into selftest/<c>/st1 after the
verifier approves; end with the report phrase "selftest st1 done". Commit messages are exactly
"selftest: st1.<n>" (the workers) and "selftest: merge st1.<n>" (the lead's merges) — never the
project's own message format or an issue number from its history.

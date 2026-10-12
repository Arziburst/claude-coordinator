# Contract — the unit of delegated work

What a worker receives (the **contract**) and what it returns (the **report**). The coordinator writes the
contract; the worker's rules come from its role, the reviewer's from [roles/verifier.md](roles/verifier.md),
so a brief carries the contract and the facts of this task, not the rules again (CORE §4, §6).

The format is a YAML header, checked by eye or by a script, and a short free-text body. It replaces a
free-form Definition of done; the content is the same (ordered pass criteria, the evidence expected,
non-goals, "do not decide" items), made explicit so nothing is lost in the hand-off.

## The contract

```yaml
---
id: 37                             # the task's number in the tracker
title: Items with a reticle per hand
intent: >                          # why this matters, 1-3 sentences - the field most often lost in a hand-off
  The player must see which item each hand points at, so they do not grab the wrong one.
inputs:                            # exact pointers, not "the whole project"
  - src/vr/hands/*.cpp
  - docs/decisions.md#D-12
  - "S-3 Figma: inventory screen"  # sources by id (procedures/SOURCES.md)
outputs:
  - a PR into main from 37-feat-hand-reticle
acceptance:                        # ordered; each criterion says how it is checked
  - criterion: each hand shows its own reticle
    check: oracle                  # oracle | review | owner
    how: test_vr_reticle (new) passes
    source: S-3                    # where the criterion comes from; none = the coordinator's own reading
  - criterion: grabbing items does not regress
    check: oracle
    how: the existing tests/vr suite passes
  - criterion: the code follows the project's standards
    check: review
non_goals:
  - no changes beyond the fix, its diagnostics and its test
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide:                     # raised as questions, never decided by the worker
  - the reticle's colour and shape
budget:
  model: opus                      # per CORE §7: rendering and input are "hard or risky"
  effort: high
  escalate_to: fable               # model for a retry after a failed review or a stuck worker
  cost: 16                         # USD at list price: the whole task, its tests and review (CORE §7a)
depends_on: [31]
touches: [src/vr/hands/]           # what it will change, for conflict foresight (CORE §4a)
---
Free text: context, known traps, parallel work nearby, launch and test limits, the report phrase.
```

- **`check`** names how each criterion is decided: `oracle` (a test, CI, a run, a primary source, a
  calculation — something other than an opinion), `review` (the independent reviewer reads it), `owner`
  (only the owner can accept it). A criterion with no nameable check is a planning gap: fix it before
  the work starts.
- **`source`**: the catalog id the criterion comes from (procedures/SOURCES.md); the verifier checks the
  result against it. No source → the brief says the criterion is the coordinator's own reading.
- **`non_goals`**: the two lines above are the default for every contract; add the task's own.
- **`cost`**: the coordinator's estimate in dollars at list price (CORE §7a) — cost, not tokens: most
  tokens are cheap cache reads, so a token count measures context times turns, not spend. A lead fits
  its sub-contracts inside it and stops to ask when a run goes over twice its own estimate.
- **`escalate_to`**: when a worker's result fails review for a reason a stronger model would fix, or the
  worker is stuck, the coordinator restarts the contract on this model with the failed report attached
  (CORE §7).

## The report

```yaml
---
contract: 37
status: ready                      # ready | blocked | failed
model: opus
results:
  - criterion: each hand shows its own reticle
    evidence: oracle               # oracle | claim | owner
    proof: "CI run #812 on 5f3e2a1: test_vr_reticle passed"   # a CI run names the commit it ran on
  - criterion: the code follows the project's standards
    evidence: claim
questions: []                      # do_not_decide items and new forks
known_gaps:
  - not run on the headset: no device
---
```

A **lead** (roles/lead.md) adds `runs` — one entry per run under it, its own session last; tokens and
cost are read with `scripts/session-tokens`, never self-reported (`source`: `status` — the status
line's cost; `prices` — the transcript's tokens per model times the ladder's list prices), and the
coordinator copies them into the run log (CORE §7):

```yaml
runs:
  - {task: 37.1, role: worker, model: sonnet, effort: medium, estimate: 2.5, cost: 3.1, tokens: 5200000, source: status, result: approved}
  - {task: 37, role: lead, model: opus, effort: medium, estimate: 12, cost: 9.4, tokens: 19800000, source: prices, result: ready}
```

**Evidence classes.** A worker marks a result `oracle` only with a pointer to the proof (a CI run, a log,
a command and its output); everything else is `claim`; a `check: owner` criterion is `owner` until the owner accepts it (the steps
are in the report). Only the reviewer can turn a claim into
`review`-confirmed, and only an oracle the reviewer has seen counts as `oracle` in the verdict. **A CI run
is an oracle only for the commit it ran on:** its proof names the run and that commit, and it counts
for a verdict only when that commit is the head the reviewer reviewed — a run on an older head is a
`claim`. Reports,
the journal and the owner's summary keep the class, so "tested", "reviewed" and "said so" never look the
same.

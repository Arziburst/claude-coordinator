# Contract — the unit of delegated work

What a worker receives (the **contract**) and what it returns (the **report**). The coordinator writes the
contract; the worker's rules come from its role, the reviewer's from [roles/verifier.md](roles/verifier.md),
so a brief carries the contract and the facts of this task, not the rules again (CORE §4, §6).

The format is a YAML header, checked by eye or by a script, and a short free-text body. It replaces a
free-form Definition of done with the same content — ordered pass criteria (the `acceptance` list), the
evidence expected, non-goals, "do not decide" items — made explicit so nothing is lost in the hand-off.

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
tests_first: yes                   # an oracle criterion names a new test (CORE §4 step 3)
non_goals:
  - no changes beyond this contract's acceptance, its diagnostics and its tests
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide:                     # raised as questions, never decided by the worker
  - the reticle's colour and shape
budget:
  model: opus                      # per CORE §7: rendering and input are "hard or risky"
  effort: high
  escalate_to: fable               # model for one retry after a failed review
  cost: 16                         # USD at list price: the whole task, its tests and review (CORE §7a)
  time: 18-40                      # optional: minutes of work, the median's range (CORE §7a)
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
- **`tests_first`**: `yes` — the tester writes the red tests before the worker starts (CORE §4 step 3) —
  or `no` with its reason (`no - the criteria are covered by existing tests`). Required: a decision,
  never a default; `yes` for every §5 change and every `oracle` criterion whose test does not exist yet.
  A contract written before the field existed needs none while its session is only resumed; it gets
  the field when it is next written or changed, since check-contract runs before each delegation. A
  task given to a lead: its sub-contracts carry the field, and the lead runs the tester for each `yes`
  (roles/lead.md step 3).
- **`cost`**: the coordinator's estimate in dollars at API list price (CORE §7a, `scripts/run-stats`):
  on a subscription the unit of forecasting, not a charge; a real charge only with usage credits on or
  with an API key. Cost, not tokens: most tokens are cheap cache reads, so a token count measures
  context times turns, not spend. A lead fits its sub-contracts inside it and
  stops to ask when a run goes over twice its own estimate.
- **`time`** (optional): the forecast work in active minutes, a number or a range (`25`, `18-40`), from
  `scripts/run-stats`, measured from the transcripts, owner waits never in it (CORE §7a). check-contract
  warns only when it is there and is neither; a contract without it is fine.
- **`escalate_to`**: when a worker's result fails review for a reason a stronger model would fix, the
  coordinator restarts the contract on this model with the failed report attached (CORE §7) — once, the
  top rung only within CORE §7's guard rails (else Opus at its highest effort); a second failure goes
  to the owner, not to another restart. A stuck worker (a `blocked` report) is helped or split
  (CORE §4), which spends no escalation. A model that is not stronger than `model` gives no second
  chance: check-contract warns.

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
core_findings: []                  # a suspected fault of the core itself, with evidence (procedures/CORE-FINDINGS.md)
---
```

A **lead** (roles/lead.md) adds `runs`: one entry per run under it, its own session last. Tokens,
cost and time are read with `scripts/session-tokens`, never self-reported (`source`: `status` — the
status line's cost; `prices` — the transcript's tokens per model times the ladder's list prices;
`start`, `wall`, `active` — its `time` line, minutes; a cost at API list price, as `cost` above). The
coordinator copies them into the run log (CORE §7):

```yaml
runs:
  - {task: 37.1, role: worker, model: sonnet, effort: medium, estimate: 2.5, cost: 3.1, tokens: 5200000, source: status, result: approved, start: 2026-10-05T09:12:40Z, wall: 48, active: 31, estimate_time: 25-40}
  - {task: 37, role: lead, model: opus, effort: medium, estimate: 12, cost: 9.4, tokens: 19800000, source: prices, result: ready, start: n/a, wall: n/a, active: n/a, estimate_time: 60-90}
```

**Evidence classes.** A worker marks a result `oracle` only with a pointer to the proof (a CI run, a
log, a command and its output); everything else is `claim`; a `check: owner` criterion is `owner`
until the owner accepts it (the steps are in the report). Only the reviewer can turn a claim into
`review`-confirmed, and only an oracle the reviewer has seen counts as `oracle` in the verdict. **A CI
run is an oracle only for the commit it ran on:** its proof names the run and that commit, and it
counts for a verdict only when that commit is the head the reviewer reviewed — a run on an older head
is a `claim`. A check the reviewer may not run (a shared device, a lock) can rest on the worker's raw
output for the reviewed commit, attached where `how` says: it is shown as `oracle (worker's run,
<commit>)`, never as plain `oracle` (CORE §6). Reports, the journal and the owner's summary keep the
class, so "tested", "reviewed" and "said so" never look the same.

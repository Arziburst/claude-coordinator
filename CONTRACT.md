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
title: Saved carts per account
intent: >                          # why this matters, 1-3 sentences - the field most often lost in a hand-off
  A signed-in customer finds the same cart on every device, so they do not lose what they picked.
inputs:                            # exact pointers, not "the whole project"
  - src/cart/*.ts
  - docs/decisions.md#D-12
  - "S-3 Figma: cart screen"       # sources by id (procedures/SOURCES.md)
outputs:
  - a PR into main from 37-feat-saved-cart
acceptance:                        # ordered; each criterion says how it is checked
  - criterion: a cart saved on one device opens on another
    check: oracle                  # oracle | review | owner
    how: test_cart_sync (new) passes
    source: S-3                    # where the criterion comes from; none = the coordinator's own reading
  - criterion: checkout does not regress
    check: oracle
    how: the existing tests/cart suite passes
  - criterion: the code follows the project's standards
    check: review
tests_first: yes                   # an oracle criterion names a new test (CORE §4 step 3)
non_goals:
  - no changes beyond this contract's acceptance, its diagnostics and its tests
  - do not weaken or loosen tests, timeouts or tolerances
do_not_decide:                     # raised as questions, never decided by the worker
  - how long a saved cart is kept
budget:
  model: opus                      # per CORE §7: stored customer data is "hard or risky"
  effort: high
  escalate_to: fable               # model for one retry after a failed review
  cost: 16                         # USD at list price: the whole task, its tests and review (CORE §7a)
  time: 18-40                      # optional: minutes of work, the median's range (CORE §7a)
depends_on: [31]
touches: [src/cart/]               # what it will change, for conflict foresight (CORE §4a)
bounds:                            # with tests_first: yes, or when touches holds an important component: the most lines a glob may add
  - src/cart/* 120
  - tests/cart/* 80
wall: the server checks the account on every read; the cart screen only filters  # what really protects it
---
Free text: context, known traps, parallel work nearby, launch and test limits, the report phrase.
```

- **`check`** names how each criterion is decided: `oracle` (a test, CI, a run, a primary source, a
  calculation — something other than an opinion), `review` (the independent reviewer reads it), `owner`
  (only the owner can accept it). A criterion with no nameable check is a planning gap: fix it before
  the work starts.
- **Test access points:** an interface a test needs (a status field, a flag, an endpoint, a command, a
  test hook) is named in the contract — in a criterion or the free text — or by the tester at the top of
  its test file; the worker implements it as written (#237).
- **`source`**: the catalog id the criterion comes from (procedures/SOURCES.md); the verifier checks the
  result against it. No source → the brief says the criterion is the coordinator's own reading.
- **`non_goals`**: the two lines above are the default for every contract; add the task's own.
- **`tests_first`**: `yes` — the tester writes the red tests before the worker starts (CORE §4 step 3) —
  or `no` with its reason (`no - the criteria are covered by existing tests`). Required: a decision,
  never a default; `yes` for every §5 change and every `oracle` criterion whose test does not exist yet.
  A contract written before the field existed needs none while its session is only resumed; it gets
  the field when it is next written or changed, since check-contract runs before each delegation. A
  task given to a lead: its sub-contracts carry the field, and the lead runs the tester for each `yes`
  (roles/lead.md step 3); the task itself gets no task-level tester — its parent contract says
  `tests_first: no - the lead runs the tester per sub-contract`, `yes` belongs only in sub-contracts,
  and start-worker refuses a lead whose contract says `yes` or that is given the tester's flags (#289).
  start-worker enforces `yes`: no worker starts without `--tester-commit <sha>`
  or `--tester-tests <path>` (TOOLKIT *Working copies*, #276); later rounds that change behaviour start with the
  tester again (CORE §4 step 5).
- **`cost`**: the coordinator's estimate in dollars at API list price (CORE §7a, `scripts/run-stats`):
  on a subscription the unit of forecasting, not a charge; a real charge only with usage credits on or
  with an API key. Cost, not tokens: most tokens are cheap cache reads, so a token count measures
  context times turns, not spend. A lead fits its sub-contracts inside it and
  stops to ask when a run goes over twice its own estimate.
- **`bounds` and `wall`** (#381): required when `touches` holds an **important component**: a path the
  core's default list `scripts/hooks/* .github/workflows/* tests/*/run.*` or the project's `PROJECT.md` row
  *Important components* matches, or a folder holding one (a project adds, never removes a default).
  check-contract refuses such a contract without them. `bounds:` is lines `- <glob> <max added lines>`, each a
  whole number; a file no bound matches is not limited, and a bound's glob need not be the important one.
  `wall:` is one line: what really protects this component, and what this change only filters. **How a bound
  is chosen:** the smallest that can hold the criteria. A bound that cannot carry the criteria is the signal
  to ask what wall would hold, never to widen it silently. `scripts/check-bounds <contract> <base>...<head>`
  compares the real diff with the bounds: the worker and the tester run it before reporting, the verifier as
  an oracle, and `scripts/merge-queue land` on the contract it finds at `coordinator/briefs/<head branch>-contract.md`
  (a branch's `/` as `-`), then by the id the PR's branch starts with, `coordinator/briefs/<id>-contract.md`.
  At the queue (#419) an OVER stops the PR only when its glob matches or holds an important glob (the list above);
  any other OVER prints one line (`bounds over, not important: <pr> <glob> <added>/<max>`) and the PR goes on. The worker
  still stops and asks past any bound, and the verifier still reads it.
  `scripts/start-worker` saves that copy when a worker or a lead starts, in a repository with `coordinator/briefs/`,
  over an older copy and never committed (#387); a contract of a task with no `bounds:` needs no copy. A contract written before this change is not rejected at a merge:
  no `bounds:` is `check-bounds: no bounds`, exit 0. **What it does not stop:** a wrong bound, or a component
  left off the list, slips through; a glob that only overlaps an important one (`*.sh` over `scripts/hooks/x.sh`) stays
  ordinary at the queue; `--over-bounds-ok` for two PRs goes in two runs (`.ps1 -File` does not
  repeat a parameter); and the coordinator could pass an owner-ok flag on its own: only CORE §1.14 and the
  journal hold that.
- **A bound on tests** (#390): a contract with `tests_first: yes` names the size of the tests the task adds, test
  data counted: its `bounds:` hold a line whose glob takes them in, chosen as above. check-contract refuses a `yes`
  with no well-formed `bounds:` line, important component or not; `wall:` stays a rule of the important components,
  and `tests_first: no ...` needs no bound for this. A case closing a real route of a safety or money check is never
  cut for a bound; a bound too small there goes to asking. **What it does not stop:** the refusal holds only that a
  bound exists, not that it is wise or that its glob covers the tests, and a binary file counts as 0; the verifier
  and the owner hold the rest.
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
  - criterion: a cart saved on one device opens on another
    evidence: oracle               # oracle | claim | owner
    proof: "CI run #812 on 5f3e2a1: test_cart_sync passed"   # a CI run names the commit it ran on
  - criterion: the code follows the project's standards
    evidence: claim
questions: []                      # do_not_decide items and new forks
known_gaps:
  - not run on a real phone: no device
core_findings: []                  # a suspected fault of the core itself, with evidence (procedures/CORE-FINDINGS.md)
ci_seconds: +4                     # what the change adds to the full CI suite (roles/worker.md step 2)
test_edits: []                     # each edit to an existing test and why; the tester's: build-only (roles/worker.md step 2)
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

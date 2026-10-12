# Self-test

Part of the coordinator core, read when the self-test runs. Same authority as `CORE.md`; the hard rules
of CORE §1 apply.

It proves that the coordinator works **on this machine, in this environment** — the scripts under its
shells, the logins, background sessions starting further sessions, the roles, worktrees, git and gh —
with real sessions on purpose, at a small cost (measured: about $0.5 at list price, the lead most of it;
the run records the
real number). It does **not** replace the dry run (CORE §12a): the dry run checks the project's own
wrappers on a real task, the self-test checks the core and the machine in a sandbox. Both run.

## When

- **Init:** after the summary's yes and the dry run, before waiting for "start a new cycle" (CORE §2
  step 8) — the full test, once per machine: CHECKLIST row `selftest` ([ONE-TIME.md](../ONE-TIME.md)).
- **A machine with no `selftest` line** in this project's CHECKLIST: offered at the next "update the
  core" — "No self-test on this machine yet. Run it? yes/no" (UPDATE-CORE step 3).
- **After an update that changed `scripts/` or `roles/`:** the short run — steps 1, 2, 3, step 4 with
  one worker on the light model and no lead, and step 6.
- On the owner's word, any time.

## The steps

The scripted steps use `scripts/selftest` from the core copy: the `.ps1` on Windows (it runs every
`.ps1` script under Windows PowerShell 5.1 **and** pwsh where both exist), the `.sh` elsewhere. Each
prints `PASS` / `FAIL` / `SKIP` lines. Every session the test starts has `selftest` in its name, so step
6 finds what is left. Models: the light rung for everything (Haiku where the ladder has it), the lead
one rung up (Sonnet): a lead on the lightest model may fail its role, and a FAIL must mean the
environment, not the model.

1. **Scripts:** `selftest scripts` — check-core, check-scripts, check-contract on
   `tests/selftest/contract.md`, the status line and `session-tokens` on fixtures, the hook's self-test,
   and the hook allowing `selftest/*` while blocking `main` and `master`.
2. **Environment:** `selftest env --repo <owner/name>` with the project's repository when it is on
   GitHub (`gh auth status`, read-only `gh repo view` and `gh pr list`); otherwise without `--repo`
   (`n/a`). The claude, git and gh versions go into the report.
3. **Sandbox:** `selftest sandbox` prints the folder (a repository whose origin is a local bare
   repository, branch `main`) and the start time. Nothing in it leaves the machine. It is always
   `~/coordinator-selftest`, or under the folder where the owner keeps projects (`--in` / `-In`;
   BINDINGS): sessions start in a repository root that
   Claude Code trusts (TOOLKIT *Directory and trust*), and trust is kept per path, so **the owner trusts
   `<sandbox>/repo` once per machine** — and `<sandbox>/state` too where step 5
   runs — by opening `claude` there and accepting; the coordinator never writes trust itself. Not trusted
   yet → the first start-worker fails with "Workspace not trusted": ask the owner for this step, then
   continue.
4. **Mini block** in the sandbox, with the project's real start-worker (BINDINGS) and worker safety
   file:
   - **Lead:** start-worker `--repo <sandbox>/repo --branch st1-selftest --name "#st1 lead: selftest"
     --model sonnet --report-to <the coordinator>`, effort low; the brief is `roles/lead.md`, the contract
     `tests/selftest/contract.md`, the start-worker command for its workers (`--repo <sandbox>/repo
     --base st1-selftest --report-to "#st1 lead: selftest"`, the light model, effort low, at most two at once, names `#st1.<n> worker:
     selftest …`) and "no PR: merge each approved sub-branch into `st1-selftest` and push it".
   - **The budget stop:** the contract's `budget.cost` is below any real plan on purpose, so the lead
     must send its plan and start nothing (roles/lead.md step 2). When the plan arrives, the
     coordinator checks that no `#st1.<n>` session runs and the sandbox origin has no `st1-<n>-…`
     branch (`git ls-remote <sandbox>/remote.git`) — a lead that started anyway is a FAIL of the role —
     then answers "go: the budget is now <the plan's total>".
   - **Two workers** each make a branch, a commit and a push; the lead's **verifier** subagent gives a
     verdict on each; the lead merges them and reports (`runs` included).
   - **The coordinator** checks the oracles itself (`git show st1-selftest:a.txt` → `a`, `b.txt` → `b`),
     then merges locally: `git -C <sandbox>/repo merge --no-ff st1-selftest` into the sandbox's `main`
     (not pushed: the hook protects every `main`).
   - **Tester, scout, researcher:** each started as a subagent on the light model with "read your role
     file; answer in one line: your role and this contract's id (st1)". PASS when the line names both.
   - PASS when the lead stopped at the budget, its report is `ready`, both oracles hold, each sub-task
     has a verdict and the merge
     is in `main`.
5. **PR flow** — only when the state repository has a remote on the **owner's own account** (one in a
   client's or a team's organization: only on the owner's yes); no remote → `SKIP pr-flow: no remote`,
   not a FAIL.
   - Clone the state repository into `<sandbox>/state`. Read its default branch from the remote
     (`gh repo view <repo> --json defaultBranchRef --jq .defaultBranchRef.name`), never assume it;
     create `selftest/base` from it (`git push origin <default>:refs/heads/selftest/base`).
   - A worker (`#st2 worker: selftest PR`, start-worker `--repo <sandbox>/state --base selftest/base
     --branch selftest/task-1 --report-to <the coordinator>`, light model) adds one file, commits, pushes and opens a **draft** PR
     into `selftest/base`.
   - A verifier subagent reviews it and posts its verdict as a PR comment.
   - The coordinator marks it ready (`gh pr ready`), squash-merges it (`gh pr merge --squash`), checks
     `gh pr view --json state` → `MERGED`, runs **cleanup-worker** on the worker's worktree (it must
     report cleaned: a merged PR with the pushed head), then deletes both branches
     (`git push origin --delete selftest/task-1 selftest/base`).
   - Nothing is ever pushed to the default branch.
6. **Cleanup:** stop and remove every `selftest` session (`claude stop`, then `claude rm`, each its own
   command); read each one's cost with `scripts/session-tokens <id>` and delete its status file
   (TOOLKIT *Usage*); then `selftest clean --sandbox <dir> [--state-repo <owner/name>]` — no worktree,
   branch, session or `selftest/*` branch left, then the sandbox folder is removed.
7. **Report:** one table — step · PASS / FAIL / SKIPPED · evidence — and the run's cost (the sum of
   step 6). A line in `coordinator/CHECKLIST.md`: `selftest`, the core commit, `hostname`, `done` or
   `failed` (`short` in the note for the short run).

## A FAIL that comes from the core

A FAIL whose cause is a core script, role or procedure (not the project or the machine):

1. Write a **sanitized report**: the core commit; OS and version, shell and PowerShell versions,
   claude, git and gh versions; the step, the command, its exit code and error lines. Project names
   and paths become `<project>` / `<path>`; no tokens, no customer data (CORE §1.13).
2. Show it to the owner and ask once: "Send this report to claude-coordinator as an issue? yes/no".
3. **Yes**, with the owner's own gh login: `gh issue create -R Arziburst/claude-coordinator --title
   "selftest: <step> fails on <os>" --label selftest-report --body-file <report>` (the label created
   first with `gh label create` if missing); print the link. A fix found and checked goes as its own
   draft PR through claude-coordinator's change path, on the owner's yes.
   No write access or no gh → print the report for the owner to send by hand.
4. **No** → keep it in `coordinator/selftest/<date>.md`.

The maintainer triages issues labelled `selftest-report`: reproduce, fix in a PR that names the issue,
close it with the fixing commit.

## Not covered

The real project's CI and its branch protection: the sandbox has neither. The first real PR of the
first cycle is watched end to end as the last check (CHECKLIST `first-real-pr-watched`).

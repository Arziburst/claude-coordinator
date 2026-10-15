# Self-test

Part of the coordinator core, read when the self-test runs. Same authority as `CORE.md`; the hard rules
of CORE §1 apply.

It proves that the coordinator works **on this machine, in this environment, at this core commit** —
the scripts under its shells, the logins, background sessions starting further sessions, the roles,
worktrees, git and gh — with real sessions on purpose, at a small cost (measured: about $0.5 at list
price, the lead most of it; the run records the real number). It runs in the project's own **state
repository** (`coordinator/`) and **keeps its branches and its PR as evidence** that this core commit
passed here, so the owner can go back to a proven version. It does **not** replace the dry run (CORE
§12a): the dry run checks the project's own wrappers on a real task; both run.

## When

- **At init:** after the summary's yes and the dry run, before waiting for the owner's first task (CORE §2
  step 8).
- **After every "update the core"** (UPDATE-CORE step 4): the full test, at the new commit.
- On the owner's word, any time. A commit already tested here (its `selftest/<commit>/base` exists) is
  not tested again unless the owner deletes that evidence himself.

Each run is one CHECKLIST line `selftest` ([ONE-TIME.md](../ONE-TIME.md)) naming the core commit and the
machine.

## Where — no sandbox, no new trust

- The test's branches live in the **state repository**: `selftest/<commit>/base` (from the state
  branch), `selftest/<commit>/st1` (the lead's integration branch), `selftest/<commit>/st1.<n>` (its
  workers), `selftest/<commit>/task-1` (the PR flow). Nothing is ever merged into the state branch.
- Their **worktrees** live under the project's trusted root, `<project>/.claude/worktrees/` (the
  project's git ignores it — `selftest prepare` checks and, if needed, adds it to `info/exclude`).
- Every test session starts from the **project root** (trusted at init) with start-worker
  `--repo <project>/coordinator --launch-from <project> --worktree-root <project>/.claude/worktrees`:
  start-worker then tells it to work in its worktree **by absolute path, without EnterWorktree**
  (EnterWorktree into another repository's worktree asks for permission and the session would wait;
  TOOLKIT *Directory and trust*). No folder needs a new trust.
- A state repository without a remote: the same flow with local branches and a local merge; step 5
  is `SKIP pr-flow: no remote`, not a FAIL.

## The steps

The scripted steps use `scripts/selftest` from the core copy: the `.ps1` on Windows (it runs every
`.ps1` script under Windows PowerShell 5.1 **and** pwsh where both exist), the `.sh` elsewhere. Each
prints `PASS` / `FAIL` / `SKIP` lines. Every session the test starts has `selftest` in its name, is
subscribed right after its start (CORE §4, *Control*) and reports to the coordinator's current name
(`--report-to`). Models: the light rung for everything (Haiku where the ladder has it), the lead one
rung up (Sonnet): a lead on the lightest model may fail its role, and a FAIL must mean the
environment, not the model. `<c>` below is the core commit under test.

**Limits.** Before step 4, check the windows have room for the run (about $0.5, in limit percent by
the ratio of CORE §7a; the status line, TOOLKIT *Usage*); no room → wait for the reset or ask the owner.
A limit hit mid-run (a 429 "You've hit your … limit", a session `blocked`) → pause until `resets_at`,
then resume each blocked test session as TOOLKIT *Usage* says (respawn **and** a "continue" message);
the report notes the interruption and the resume time.

1. **Scripts:** `selftest scripts` — check-core, check-scripts, check-contract on
   `tests/selftest/contract.md`, the status line and `session-tokens` on fixtures, the hook's self-test,
   and the hook allowing `selftest/*` while blocking `main` and `master`.
2. **Environment:** `selftest env --repo <owner/name>` with the project's repository when it is on
   GitHub (`gh auth status`, read-only `gh repo view` and `gh pr list`); otherwise without `--repo`
   (`n/a`). The claude, git and gh versions go into the report.
2a. **The guard, through Claude Code.** The guard's own self-test calls it directly; only a real
   session shows whether Claude Code honours its block (a PowerShell shell wrapper, a broken path).
   - `selftest hooks --settings <file>` on the worker safety file and on every settings file of the
     coordinator's own session that holds the guard (the project's `.claude/settings.json` and
     `.claude/settings.local.json`, the user's `~/.claude/settings.json`).
   - Two probe sessions on the light model, started from the project root (trusted): one with
     `--settings <worker safety file>`, one with no `--settings` (it loads the settings the coordinator
     itself runs with). Each is told: "Run exactly `git push origin HEAD:main --dry-run`, report its
     output, stop." Then `selftest hookcheck --session <id>` for each: PASS only on the block; a
     non-blocking error or no hook at all is a FAIL — a FAIL in the coordinator's own settings is
     fixed before anything else. Then their cost is read and they are removed (step 6's order).
     **No guard in the coordinator's own settings** (none of the files above holds one: the core does
     not require it there, TOOLKIT *New machine*) → the second probe is not started; the report says
     `SKIP probe (own settings): no guard there`. Putting the guard there is the owner's choice
     (CORE §1.16), offered once, never made by the coordinator.
   - **Probe names:** each probe session is named `probe: …` (`--name "probe: push"`, `"probe: push (own
     settings)"`, `"probe: edit"`): `selftest verify` and `clean` find the self-test's sessions by that name
     (or `selftest`, or a `#st` task), and the retro leaves them out.
   - **The edit probe**, when the worker safety file sets `COORD_PROTECTED_ROOT` (TOOLKIT *Safety*): a
     third probe session on the light model, started from the project root with `--settings <worker
     safety file>`, told: "Use the Write tool to create `<root>/probe-root.txt` containing x; do not
     retry another way; report, stop." Then `selftest hookcheck --session <id> --expect edit`: PASS only
     on the guard's working-copy block; a write that went through, no hook or a non-blocking error is a
     FAIL, fixed before anything else, like the push probe (a `probe-root.txt` left in the root is
     removed by the owner or the coordinator). Its cost is read and it is removed like the others. Not
     set → `SKIP probe (edit): COORD_PROTECTED_ROOT not set`.
   - A settings file fixed during the test is proven again in a **new** session: hooks load at start.
3. **Prepare:** `selftest prepare --project <root> --state <root>/coordinator --core <c>` — the
   project's git ignores `.claude/worktrees`; `selftest/<c>/base` is created from the state branch and
   pushed where there is a remote. It refuses a commit already tested here. It also checks
   `coordinator/CORE-FINDINGS.md`: present, with the template's table header, every row's status a
   known one.
4. **Mini block**, with the project's real start-worker (BINDINGS) and worker safety file:
   - **Lead:** start-worker (the flags above) `--branch selftest/<c>/st1 --base selftest/<c>/base
     --name "#st1 lead: selftest" --model sonnet --report-to <the coordinator>`, effort low; the brief
     is `roles/lead.md`, the contract `tests/selftest/contract.md` with `<c>` filled in, and the
     start-worker command for its workers (the same flags, `--base selftest/<c>/st1`, branches
     `selftest/<c>/st1.<n>`, `--report-to "#st1 lead: selftest"`, the light model, effort low, at most
     two at once, names `#st1.<n> worker: selftest …`): "no PR: merge each approved sub-branch into
     `selftest/<c>/st1` and push it where there is a remote".
   - **The budget stop:** the contract's `budget.cost` is below any real plan on purpose, so the lead
     must send its plan and start nothing (roles/lead.md step 2). When the plan arrives, the
     coordinator checks that no `#st1.<n>` session runs and no `selftest/<c>/st1.<n>` branch exists —
     a lead that started anyway is a FAIL of the role — then answers "go: the budget is now <the plan's
     total>".
   - **Two workers** each make a branch and a commit (and a push where there is a remote); the lead's
     **verifier** subagent gives a verdict on each; the lead merges them and reports (`runs` included).
   - **The coordinator** checks the oracles itself (`git show selftest/<c>/st1:a.txt` → `a`, `b.txt` →
     `b`), then merges `selftest/<c>/st1` into `selftest/<c>/base` (a worktree of the base under
     `.claude/worktrees/`, `merge --no-ff`, pushed where there is a remote).
   - **Tester, scout, researcher:** each started as a subagent on the light model with "read
     `<core>/roles/<role>.md` (the absolute path); answer in one line: `role: <the name in its
     frontmatter>; contract: st1`". PASS only when the line gives the exact role name (`tester`,
     `scout`, `researcher`) and `st1`: a subagent that did not find the file answers from its system
     prompt ("test-writer"), which proves nothing.
   - PASS when the lead stopped at the budget, its report is `ready`, both oracles hold, each sub-task
     has a verdict and `st1` is merged into the base.
5. **PR flow** — where the state repository has a remote on the **owner's own account** (one in a
   client's or a team's organization: only on the owner's yes):
   - A worker (`#st2 worker: selftest PR`, start-worker with the flags above, `--branch
     selftest/<c>/task-1 --base selftest/<c>/base --report-to <the coordinator>`, light model) adds one
     file, commits it as exactly `selftest: task-1` (never the project's own message format or an issue
     number from its history), pushes and opens a **draft** PR into `selftest/<c>/base`. Its brief says to push
     **without** `-u` (`git push origin selftest/<c>/task-1`) on purpose, so every run proves
     cleanup-worker's fallback to `origin/<branch>` (roles/worker.md pushes with `-u`).
   - A verifier subagent reviews it and returns its verdict (it changes nothing, roles/verifier.md);
     the coordinator posts that verdict as a PR comment.
   - The coordinator marks it ready (`gh pr ready`), squash-merges it (`gh pr merge --squash --match-head-commit <the commit the verdict names>`, never
     `--delete-branch`), checks `gh pr view --json state` → `MERGED`, stops the worker (`claude stop`), reads
     its spend and deletes its status file (step 6's order), and runs **cleanup-worker** on the
     worker's worktree with `--session` (its short id or full `sessionId`; it must report cleaned: a
     merged PR with the pushed head, the session gone — `SESSION KEPT`, exit 4, is a FAIL). A merge refused by
     the auto mode's classifier goes to the owner as the exact `! gh pr merge …` command (TOOLKIT
     *Modes*); the step continues once `state` is `MERGED`.
   - Nothing is pushed to or merged into the state branch.
6. **Verify and clean up:** for every `selftest` session (each `#st…` and probe session too), in this
   order — `<id>` is the **short** id (`id` in `claude agents --json`; stop and rm refuse the full
   `sessionId`, which only `--resume` takes, TOOLKIT *Workers*): `claude stop <id>`, read its
   cost with `scripts/session-tokens <id>` (the full command, TOOLKIT *Scripts*; a failed read is
   retried once, never left as `n/a`; it now comes from the record the stop wrote — a read still
   showing `out>=` had none, a crash: read as before and noted in the report), delete its status file
   (TOOLKIT *Usage*), then `claude rm <id>` (each its own command); then `selftest verify --project
   <root> --state <root>/coordinator --core <c> [--state-repo <owner/name>]` — no session or worktree left (a session
   is any that `claude agents --json --all` lists, `done` too, named with `selftest` or `probe:` or
   starting with `#st`; the FAIL names each with its short id; clean, merged worktrees are
   removed; only a session whose `cwd` is inside the run's own folders counts — the project root, the
   state repository, the worktree roots of `PROJECT.md` (for `clean`: the sandbox) — while another
   project's on the same machine gets a line `SKIP foreign self-test session <id> (<cwd>)` and is never
   advised for removal), the evidence is there (`base`, `st1` merged into it, the merged PR). **No branch and no PR
   is deleted.**
7. **Report:** one table — step · PASS / FAIL / SKIPPED · evidence — and the run's cost (the sum of
   step 6). A line in `coordinator/CHECKLIST.md`: `selftest`, the core commit, `hostname`, `done` or
   `failed`.

### The core itself — a sandbox (the maintainer, CI)

Developing claude-coordinator there is no project and no state repository: `selftest sandbox [--in
<folder>]` makes a repository with a local bare origin at `<folder>/coordinator-selftest` (default:
home; a fixed path, so its `repo` is trusted once per machine; a relative `--in` is made absolute
first, since the repo's origin URL is stored from it) and records its first commit in the sandbox's
marker (`.coordinator-selftest`: `initial <commit>`, outside the repository); steps 4 and 6 run there
with the sandbox's `main` as the base.

- **Step 6 keeps the sandbox by default:** `selftest clean --sandbox <dir> --keep`. It refuses as a
  full clean does — a worktree not clean, a branch not merged into the repo's main (in the repo, or
  on the origin: both are deleted), a self-test session still listed → FAIL, the sandbox kept for
  inspection and nothing reset. Otherwise every worktree and every branch but `main` goes, in the repo
  and in its origin; `main` of both goes back to the first commit; the repo's untracked files go
  (`git clean` on the repo only); the folder, the marker, the repo's path and `remote.git` stay —
  "sandbox kept for the next run".
- **`.claude/settings.local.json` in the repo stays** through `clean --keep`, although untracked: it
  holds the permissions the owner gave the sandbox's sessions ("don't ask again"), which, like the
  trust, should not be asked for again on the next run. It does not stop the sandbox from being reused.
- The next `selftest sandbox` **reuses** a kept sandbox (`PASS sandbox: reusing the kept sandbox …`);
  one left not clean is refused until `selftest clean --sandbox <dir> [--keep]` runs; any other
  existing folder is refused.
- A full `selftest clean --sandbox <dir>` (no `--keep`) removes the folder, when the owner wants it
  gone; the next run then needs the trust again. A sandbox kept by an older core (no first commit in
  its marker) is adopted by `clean --keep`: main's single root commit, on the origin too, is recorded
  and the sandbox is reset and kept (two roots: refused, and only a full `clean` is left).
- **Trust, on the first run only:** the owner opens `claude` once in `<dir>/repo` and accepts the trust
  prompt (the owner's own step, TOOLKIT *Directory and trust*). The kept sandbox keeps that path, so
  later runs do not ask again.

## A FAIL that comes from the core

A FAIL whose cause is a core script, role or procedure (not the project or the machine) is a **core
finding**: a row in `coordinator/CORE-FINDINGS.md` with the step, the command, its exit code and error
lines, sent to claude-coordinator as the owner chose (title `selftest: <step> …`, prefixed once) — the one
channel of [CORE-FINDINGS.md](CORE-FINDINGS.md). The next update proves the fix with the same step.

## Not covered

The real project's CI and its branch protection: the test's branches have neither. The first real PR
is watched end to end as the last check (CHECKLIST `first-real-pr-watched`).

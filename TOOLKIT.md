# Toolkit — Claude Code mechanics for a coordinator

How a coordinator does its job with Claude Code on **any machine** (Windows, macOS, Linux). This file
tracks Claude Code features and changes with them — re-check the linked docs when something behaves
differently. Items marked *(unconfirmed)* were not stated in the docs; verify them in the dry run (CORE §12a).

## Workers: start, name, manage
- **Background session per worker:** `claude --bg --name "#<task> worker: <title>" --model <model> --permission-mode <mode> "<brief>"`
  — prints an id; `claude agents [--json]`, `claude logs <id>`, `claude attach <id>`, `claude stop <id>`,
  `claude respawn <id>`, `claude rm <id>`. `--bg` cannot be combined with `-p`.
  [agent-view](https://code.claude.com/docs/en/agent-view.md), [cli-reference](https://code.claude.com/docs/en/cli-reference.md)
- **Name every session** (CORE §4): `--name` / `-n`; without it the name is auto-generated and the owner
  cannot tell sessions apart. The name carries the role, not the project (CORE §4): `#37 worker: <title>`.
- **Session or subagent, per role:** `worker` — a background session in its own working copy (named
  `#<task> worker: …`); `verifier` — a background session (`#<task> verifier: …`), or a subagent where
  `PROJECT.md` allows; `lead` — a background session (`#<task> lead: …`) in its integration branch's
  working copy, started like a worker, which itself starts its workers (`#<task>.<n> worker: …`) and
  runs tester, verifier and scout as its own subagents — a background session can start
  further background sessions (confirmed on Claude Code 2.1.296, Windows); if a version refuses, the
  lead sends its start-worker commands to the coordinator, which runs them; `researcher` — a subagent, or a session (`researcher: <topic>`) for long research;
  `tester` and `scout` — subagents only. A subagent has no session of its own: it appears inside the
  session that started it, under its role name.
- **The coordinator's own name** (CORE §2 step 1): the coordinator name in `PROJECT.md` *Settings*,
  `<Project> Coordinator` by default (INIT 3.1, question 10). It must contain the English word
  `Coordinator`: the roles' fallback looks for it when a report address fails. Several projects on one
  machine each have a coordinator, and a bare name shared by two is ambiguous for SendMessage, so the
  project's short name goes in front. Started by the owner from the CLI: `claude --name "<name>"`; in a
  running session the owner types `/rename <name>` (or Ctrl+R in agent view) — a session cannot rename
  itself, and no CLI command renames a running one (`claude --bg --resume <id> --name …` starts a
  copy). `claude agents --json` shows each session's `name`, `cwd`, `id` and `sessionId`; only the name
  works as a SendMessage address, and only the name survives a `claude respawn` (2.1.296).
- **Model:** `--model`. **Effort** for `--bg` *(unconfirmed)* — put the effort in the brief if no flag works.
- **Directory and trust:** the folder a session starts in must already be trusted, or `--bg` fails with
  "Workspace not trusted". Trust is **not inherited** from a parent folder, so a new worktree is never
  trusted (confirmed on Claude Code 2.1.296, Windows). start-worker therefore starts the session in
  the **repository root**, which the owner trusts once, and the brief's first line enters the worktree
  with the `EnterWorktree` tool (`path` of a worktree of that repository — no prompt; a worktree of
  another repository asks for permission and the session waits). Trusting a folder is the **owner's**
  step — never written into config by the coordinator.
- **Headless alternative:** `claude -p "<prompt>" --output-format stream-json --max-turns N` for short,
  non-interactive jobs (no idle notices, no messages).
- **Subagents vs sessions:** subagents (the Agent tool) for short focused jobs — research, review, a
  search; up to 20 concurrent, nesting depth 3, they cannot ask the owner questions, their usage counts
  toward yours. Background sessions for real tasks: independent, visible in the session list, own
  working copy. [sub-agents](https://code.claude.com/docs/en/sub-agents.md)
- **Roles:** [roles/](roles/) holds subagent definitions — `worker`, `lead`, `tester`, `verifier`, `scout`, `researcher`. They are part
  of the core and **installed automatically, without asking**, at every start (CORE §2 step 7) and after
  every "update the core": each `roles/*.md` is copied to `~/.claude/agents/` when missing or different
  (a different file of the same name is first saved as `<name>.md.bak`; say so in one report line). The
  project's `.claude/agents/` is never written this way — that would be a project change (CORE §1.1). A
  subagent then starts as that role; a background session (a worker, usually) gets the file's body at the top of its brief (start-worker puts
  it there from the role in the session name, `#<task> <role>: …`, unless the brief already holds it) and its
  model from `--model`. `~/.claude/agents/` serves every project on the machine, so it holds the
  **upstream** roles only: a role this project edited in its local core is never installed (another
  project would overwrite it) — the coordinator starts that subagent as a general one with the local
  role file's body at the top of its prompt and the role's model. A role's `model:` names a model, not a rung
  (CORE §7): where the ladder lacks it, the coordinator passes the ladder's model for that rung as the Agent
  tool's `model`. Check the frontmatter fields (`name`,
  `description`, `tools`, `model`) against the sub-agents docs in the dry run.
- **Lessons:** a session's message address can change after `respawn` — list sessions again and use the
  bare name; a background session idle with nothing running may exit (`done`, unreachable by
  SendMessage; 2.1.296) — a lead or a worker that still expects a message keeps a background wait
  running (roles/lead.md step 3, roles/worker.md step 3), one gone `done` is resumed (*Pause and
  resume*); remove a session with
  `claude rm` as its own command (some guards block compound removals).
- **Pause and resume a session** (a core update, the owner's request, a cap — CORE §9; measured on
  2.1.296): a session that only has to wait is told to finish its step, commit, push, report and go idle;
  a SendMessage ("continue") wakes it. To stop it outright, first record its **full** session id
  (`sessionId` in `claude agents --json` — a stopped session is no longer listed), then `claude stop <id>`.
  Resume it with `claude --bg --resume <full session id> "<message>"`, from any folder: the same id,
  worktree, name, model, permission mode, settings (the guard) and history — the subscription is renewed
  (SendMessage `notify_when_idle`) and its cost read by the same id. Never a short id (it starts a
  **copy** under a new id in the current folder, without the name: in the owner's working copy, that is a
  session working there) and never `claude resume <id>` (no such command — the id becomes a new
  session's prompt). After a pause over an hour the prompt cache is gone and the resumed session pays its
  whole history again: for a long session a fresh worker on the pushed branch with a short note may cost
  less. A lead pauses and resumes its own workers the same way; a lead gone `done` while its workers
  run is resumed by the coordinator the same way, with the worker's report that fell back to it as the
  message. A resume under a new job deletes the old job folder (`$CLAUDE_JOB_DIR/tmp`), so nothing
  durable lives there: a lead's notes go in `<its worktree>/.lead/`, the coordinator's contracts and
  briefs in the state repository (`coordinator/`). `claude respawn` is not a resume: it
  restarts a running session on a new Claude binary (and a usage-limit block, *Usage*).

## Working copies
- **The core's way:** `scripts/start-worker` creates `.claude/worktrees/<branch>` with `git worktree add`
  (branch `<issue>-<type>-<slug>`) and starts the session for it (from the repository root, *Directory and
  trust*) with `worktree.bgIsolation: "none"`, so
  Claude Code does not add a second copy; the worktrees' folder is kept out of the project's git by a
  local `.git/info/exclude` line (INIT 3.4), and a lead's notes in `<worktree>/.lead/` by another. Its built-in alternative (`claude --worktree <name>`, branch
  `worktree-<name>`) is not combined with it. Whether `git worktree add` into `.claude/` raises the
  protected-path prompt (*Safety*) *(unconfirmed)*: check in the dry run; if it does, set the
  worktree root outside `.claude/` in `BINDINGS.md`.
  [worktrees](https://code.claude.com/docs/en/worktrees.md)
- After merge: remove the worktree only if clean and fully pushed (CORE §8) — `scripts/cleanup-worker.sh`.

## Messages between sessions
- `ListAgents` + `SendMessage` (Claude uses them itself); `notify_when_idle: true` gives one notice when
  the worker is next idle (same machine, expires after 12 h). A session **waiting on a permission
  prompt is not idle**: no notice comes; `ListAgents` shows it as `waiting` (seen on 2.1.296).
- **Names change:** a restarted or renamed session may come back under another name, so a report
  address written into a brief can go stale. start-worker writes
  the address it is given (`--report-to`, the coordinator's name as `ListAgents` shows it now); the
  roles fall back to the project's Coordinator and never drop a report silently. A session the
  coordinator starts any other way (a raw `claude --bg`) has no such net: after a rename, tell every
  running session the new name (CORE §4, *Control*).
- **Subscribing right after a start can race:** the new session may not be listed yet ("No agent named
  … is reachable"). start-worker waits until `claude agents --json` lists it; if a subscribe still
  fails, retry once a few seconds later. One subscription per expected report — every re-subscription
  to an idle lead (idle while its workers run) only brings another notice for the same pause.
  [cross-session-messaging](https://code.claude.com/docs/en/cross-session-messaging.md)
- Setting **`crossSessionInbound: "accept"`** on the receiving side lets a session take
  messages unattended (`hold` / `refuse` otherwise): in the worker safety file (workers hear the
  coordinator) **and** in the coordinator's own settings (it hears its workers). Needs Claude Code v2.1.224+ (macOS / Linux / WSL2), v2.1.234+ (native
  Windows). Native Windows and WSL2 sessions cannot message each other.

## The periodic tick
- `CronCreate` / `/loop` are **session-scoped**: fire only while the session is open and idle, expire
  after 7 days, max 50 per session. `--resume` restores cron tasks (not self-paced loops). Recreate the
  tick after every restart. Durable alternatives: Routines (cloud, ≥ 1 h) or Desktop scheduled tasks.
  [scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks.md)
- A weekly job cannot live in a cron that expires after 7 days: the **weekly retro** is a due check
  instead — *last retro* in `PROJECT.md` against the last complete week, at session start, with the daily
  sync and on the tick where there is one ([procedures/RETRO.md](procedures/RETRO.md)).

## Safety
- **Permission rules:** `deny` → `ask` → `allow`; a deny always wins. Compound commands are split
  (`&&`, `;`, `|`) and every part must match an allow rule. PowerShell rules look like Bash rules:
  `PowerShell(Get-Content *)`. Read-only Bash commands are auto-allowed; PowerShell cmdlets are not.
  [permissions](https://code.claude.com/docs/en/permissions.md)
- **Never allow** patterns that run arbitrary code (interpreters, `npx`, `npm run *`, `gh api *`,
  script blocks).
- **The real enforcement is on the code host:** branch protection — PRs required, checks required, a
  human review required in the strict preset. Rules and hooks on the machine are a safety net, not a wall.
- **Hook:** a `PreToolUse` hook (`scripts/hooks/safety-guard.sh`; Windows `safety-guard.ps1`, the same
  rules, both checked against `tests/safety-guard/cases.txt`) guards only the irreversible:
  pushing, force-pushing or deleting the protected branches (main / master — in any refspec form:
  quoted, `+`, `src:dst`, `:main`, `refs/heads/` or `heads/`, `~N` / `^{}` suffixes; `--all`,
  `--mirror` and matching `:` pushes; a bare or `HEAD` push while the current branch is protected,
  following `git checkout` / `switch` (with `--track origin/main` and `-` too; `git checkout main
  <file>` restores a file and leaves the branch), `cd` / `Set-Location` and `git -C` in the same command;
  `git branch` with any delete flag, `git update-ref -d`), and removing `/`, a drive, home or a folder
  that holds it, the project's folder or a folder that holds it, or a worktree by hand (also the
  worktrees' folder and `.claude`) (`rm` / `Remove-Item` / `rd /s` in their recursive forms, `find …
  -delete` — with a test such as `-name` the project's folder may be its path —, a
  `Get-ChildItem` / `ls` piped into `Remove-Item -Recurse`, `git worktree remove --force`; a drive also
  as `/c`, `/mnt/c`, `/cygdrive/c`, home also written out in its Windows or Git Bash form, `~name` as
  a user's home for the Bash tool only; `.`, `*`, `..` and other relative targets count from the folder
  a `cd` led to, and `.` and `x/..` are taken out of the path by its text). A removal's target, an edit
  tool's path, the project's folder, home and `COORD_PROTECTED_ROOT` are also compared as they lie on
  disk — symlinks and junctions resolved for the part that exists (`cd -P`; in PowerShell the item's link
  target), `..` after a link going to its target's parent, the rest kept as written —, so a link to them
  is no way around the rules. It parses
  the command like a shell: line continuations are joined, separators inside quotes (a commit
  message, a PR body) do not split, `{ … }` groups and PowerShell script blocks split like `( … )`,
  wrappers are skipped with their options (`sudo -E`, `env -i`, `timeout 30`, `nice -n 5`, `stdbuf
  -oL`, `builtin`, `noglob`, `time`, `nohup`, `exec`; also given as a path or with `.exe`, as the
  command itself: `/usr/bin/env`, `timeout.exe`, `git.exe`), `$(…)`, `bash -c` / `pwsh -Command` (or a prefix
  such as `-Com`) and a heredoc fed to a shell
  are checked as commands of their own. Work-branch operations (push, force-push, rebase, amend,
  reset, deleting work branches) and tag-only pushes pass. Exit code 2 blocks and
  shows the reason. Input it cannot read (not a JSON object) blocks; a BOM before the object is dropped;
  only `tool_input`'s own `command` is read. A project's own patterns (`.claude/coordinator-deny.txt`,
  one regex per line, trimmed, CRLF or LF) block what they match; a pattern that cannot be read blocks
  every call (`project rule cannot be read: <line>`) until the file is fixed, and so does a deny file
  that cannot be read (no read permission — tested by opening it —, a folder) or is saved in UTF-16, as
  Windows PowerShell 5.1's `>` writes it (`… (not UTF-8: re-save it as UTF-8)`).
  **A hook that fails to run does not block** unless it says so: the guard hook carries `"onFailure":
  "block"` (Claude Code 2.1.295+; measured on 2.1.296: a wrong path let a push through with exit 127,
  with the field the call was blocked), so a broken path, a crash or a timeout fails closed. Still,
  on Windows hook commands run through
  Git Bash, so a path with backslashes (`C:\x\y`) or a PowerShell variable (`$env:CLAUDE_PROJECT_DIR`, read
  as `$env`) silently breaks it: absolute paths with forward slashes (or bash's `$CLAUDE_PROJECT_DIR`).
  **No `"shell": "powershell"` on the guard hook:** a PowerShell shell around it turns its exit 2
  (block) into 1, which Claude Code takes as a non-blocking error, and the call goes ahead (measured on
  2.1.296: `hook_non_blocking_error`, `exitCode: 1`). Where PowerShell must be the shell, the command
  ends with `; exit $LASTEXITCODE` (measured: blocks). This applies to the coordinator's own settings
  as much as to the workers'. Hooks load at session start: a fixed settings file is proven only in a
  new session. Checks: `selftest hooks --settings <file>` reads a settings file; `selftest hookcheck
  --session <id>` reads the transcript of a session told to push to `main` — the block, or the
  non-blocking error, or no hook at all. So the settings example runs the
  hook's self-test at session start (`safety-guard.sh --self-test` / `safety-guard.ps1 -SelfTest`: a
  push to `main` must block and a work-branch push must pass, so a guard that blocks everything — a
  syntax error does — fails too); a failure there means: fix before starting workers.
  That self-test calls the guard directly, never through Claude Code, so it cannot see a shell wrapper
  or a path the harness breaks — only `hookcheck` on a real session can.
  **Out of scope: deliberate evasion.** The hook catches mistakes, not a session trying to get past
  it: `eval`, `iex` / `Invoke-Expression`, `cmd /c`, `Start-Process`, `xargs` feeding a refspec,
  quoting or escaping inside a name (`ma""in`, `m\ain`, `$'main'`, `("ma"+"in")`), a branch name in a
  variable, aliases, scripts written to a file and then run, a heredoc piped into a shell. Branch
  protection on the code host is the real wall; the hook is not hardened against these on purpose.
  Hooks see only the tools their matcher names (the guard: the shell tools and the edit tools, next
  bullet) — **MCP tools are covered by deny rules only** (the settings examples
  deny the GitHub MCP write tools; rename them to the server name connected on the machine and add
  any other server that can write to a protected branch). Whether hooks run in
  `bypassPermissions` *(unconfirmed)*. [hooks](https://code.claude.com/docs/en/hooks.md)
- **The owner's working copy and the edit tools:** a worker started from the project folder
  (`start-worker` from the repository's root, EnterWorktree) works in its own copy under
  `.claude/worktrees/`, but an `Edit` / `Write` / `MultiEdit` / `NotebookEdit` with an absolute path can
  still reach the owner's checkout. With `"env": {"COORD_PROTECTED_ROOT": "<the project root>"}` in the
  **worker** safety file (never the coordinator's own settings: the coordinator edits there) and those
  four tools in the guard's matcher (`Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit`, as in the
  settings examples), the guard blocks such a call whose `file_path` (`notebook_path`) lies under the
  root, except under `<root>/.claude/worktrees/`. Both paths are compared in one form: `/` or `\`, a
  trailing separator, `.` and `..` taken out by the text (a `..` out of a worktree back into the root is
  blocked), a relative path from the call's cwd, letter case ignored on Windows and macOS (exact on
  Linux), whole path segments (`<root>-old` is another folder; the root itself is not under it).
  Unset or empty: nothing changes (opt-in). `selftest hooks --settings` checks it: set, the root must
  be an absolute path to a folder on the machine — on Windows a drive path (`C:/…`, `C:\…`, or Git
  Bash's `/c/…`, which the guard reads as `C:/…`), since Claude Code passes `C:\…` file paths there —
  and the matcher must take in the four tools; unset, a SKIP line. Through Claude Code it is proven by
  the edit probe (SELFTEST step 2a, `selftest hookcheck --session <id> --expect edit`; measured on
  2.1.296, Windows: the settings file's `env` reaches the hook). `start-worker` prints a notice when it launches a worker from the root and the safety file
  has no `COORD_PROTECTED_ROOT`. **The limit:** it guards the edit tools only — a shell command such as
  `echo x > <root>/file` or `cp` still writes there, and a symlink is not followed; it protects against
  a mistake, not intent (the worker's brief and branch protection remain the rules).
- **Deny rules** in `settings.example.json` are the swarm and standard baseline: the protected branches only
  (shell and PowerShell forms, force and mirror pushes, and the GitHub MCP write tools).
  Add `gh pr merge*` / `gh pr ready*` and the production MCP write tools in the strict preset (humans
  merge); the cautious override also adds
  `Read(**/.env*)` and the **stack candidates** the owner picks at init (never imposed), per kind:
  production database by CLI (`supabase db push*`, `psql *`, a migration repair) and by MCP
  (`mcp__<db>__execute_sql`, `apply_migration`, branch reset / merge / delete); function deploys and
  secrets; production deploys (`vercel --prod*`, `vercel promote*`, `vercel rollback*`, `vercel env *`);
  code-host settings and workflows (`gh workflow run*`, `gh secret set*`, `gh release*`, `gh api *`).
- **Protected paths:** writes into `.git` and `.claude` (including `~/.claude`) always ask, except in
  bypass mode — no allow rule pre-approves them. Write memory files with the Write / Edit tools, not
  shell commands.
- **Owner's voice (CORE §11):** the worker settings set `"attribution": {"commit": "", "pr": "",
  "sessionUrl": false}`, so commits and PRs carry no AI co-author trailer, PR line or session link; put
  the same in the coordinator's own settings (`~/.claude/settings.json`) at init. `attribution: false`
  does the same from Claude Code 2.1.281 on, but older versions skip a settings file that holds it.
  [settings](https://code.claude.com/docs/en/settings-reference.md)
- **Modes:** coordinator in `default` (or `plan` for the dry run); workers in **`auto`** in every
  preset (no permission prompts, the classifier and the hook as the net) or `acceptEdits` with the
  cautious override. `bypassPermissions` only by the owner's own explicit setup. The `auto` mode's
  classifier reviews actions rules don't settle and honors limits stated in the conversation.
  **A refusal by the classifier** (e.g. `gh pr merge` as "Merge Without Review", even after an approved
  verdict) is never retried in another form — that would work around the net: the session hands the
  owner the exact command to run with the `!` prefix (`! gh pr merge <n> --squash --match-head-commit
  <sha>`), waits for its result, and continues from there; a worker asks its coordinator, which asks
  the owner.
  [permission-modes](https://code.claude.com/docs/en/permission-modes.md)

## Scripts
One style for every script in `scripts/`, so each runs on a bare Mac and a bare Windows machine:
- **A pair with the same behaviour and output:** `<name>.sh` for macOS / Linux and `<name>.ps1` for
  Windows. Same arguments, same messages, same exit codes; a change to one is made to the other in the
  same pull request.
- **Run a `.ps1` with its full command** on Windows: `powershell -NoProfile -ExecutionPolicy Bypass
  -File <script> …` (or `pwsh` the same way). A bare `.\script.ps1` or `-File` without `-ExecutionPolicy
  Bypass` is refused under the default execution policy — a lead's cost read failed that way. Briefs
  and role files give the full command.
- **Nothing to install.** `.sh`: bash 3.2 (the macOS default) with POSIX tools as macOS ships them
  (BSD `sed` / `awk` / `find`: no GNU-only flags, no `sed -i`, no `mapfile`, no `\{?`-style regex
  escapes). `.ps1`: Windows PowerShell 5.1 (also runs under PowerShell 7); ASCII source (write `§` as
  `[char]0x00A7`: 5.1 reads a BOM-less script as ANSI). In a double-quoted string or here-string,
  a variable followed by `:` is read as a drive-qualified name and the file stops parsing:
  write `"${Issue}: $title"`, not `"$Issue: $title"` (it broke a project's start-worker wrapper).
  No Python, Node, jq or other runtimes; only `git`, `gh` and `claude`, which the coordinator needs anyway.
- **Top comment** = usage, what it checks or changes, and its exit codes; a usage error prints it.
- **CI runs both** (`.sh` with bash, `.ps1` with `pwsh`) where the script can run in CI.
- **Arguments:** the same names, in each shell's own form: `--brief-file` in `.sh`, `-BriefFile` in `.ps1`.
- Exceptions: `statusline.sh` needs `jq` for its display line (it saves the status file without it);
  `hooks/safety-guard.sh` uses `jq` when present and reads the JSON with `sed -E` and `awk` otherwise
  (both paths pass the same cases; CI runs it without `jq` and with macOS `/bin/bash`).
- **Tests:** `tests/safety-guard/run.sh <hook command>` (the shared verdicts and the hook's self-test) and
  `tests/workers/run.sh sh|ps <powershell>` (start-worker / cleanup-worker against temporary
  repositories with stub `claude` and `gh`; the real `claude` is never called). The others take the same
  `sh|ps <powershell>`: `tests/check-contract/run.sh` (the fixture contracts against their expected
  output), `tests/check-core/run.sh` (a core copy with a wrapped feature field and a script without its
  pair), `tests/check-scripts/run.sh` (odd folder names, extensions in capitals, 5.1's rules, a `bash`
  that checks nothing), `tests/session-tokens/run.sh` (the fixture transcripts counted exactly, their time lines included),
  `tests/session-insights/run.sh` (fixture transcripts: guard blocks followed by a retry, a way around,
  a change and a stop, a deny rule, refusals by another hook, the classifier, a safety check and the
  user, tool errors and a repeat, errors that are only an exit code, waits, rereads, a cache rewrite, a subagent,
  `--since` across two sessions, CRLF, a BOM and malformed lines; `--until`, `--skip-tests` and `--project`
  on `tests/retro/claude/`), `tests/retro/run.sh` (a run log with a history, a thin previous week, a week
  with a rework, an escalation, a failed run, a lead and a subagent row, a project's own kind and an open
  wait, a self-test and a probe left out; its journal, escapes and transcripts; the local report and the
  public body against their expected files, the folder's name absent from the public body, a week with too
  little data and no transcripts, CRLF and a BOM; the public check failing on an injected path, the
  folder's name, free text and a foreign label; the proposal check; `--new-id`; usage errors),
`tests/run-stats/run.sh` (fixture run logs: a task's worker, tester and verifier rows summed, a lead
and its sub-runs summed, only the last 10 tasks counted, old rows without the time columns, `-`
values, under 4 tasks, even counts, `--per-run`, no header or one in another order, a header only,
CRLF with a BOM, a missing file; `--limits` on `tests/run-stats/limits/`: trusted, guessed and previous
ratios, a block that fits and one that does not, a window that has reset, no `rate_limits`, CRLF with a
BOM, models priced apart),
  `tests/selftest/hooks.sh` (every settings fixture against its expected output, the steps' usage
  errors), `tests/selftest/prepare.sh` (prepare and verify: CORE-FINDINGS.md, a base only on the remote,
  a non-ASCII folder) and `tests/selftest/core-copy.sh` (the checks on a project's cloned core copy). On
  Windows, the ones that read native output or print `§` run the `.ps1` with the console on code page 866,
  as on a Russian Windows.

## CI
- **Watch the current head's run.** A new push cancels the running CI of its branch (concurrency), so
  a watcher on the old run sees `cancelled`, which is no failure: watch the run of the PR's current
  head (`gh pr view <n> --json headRefOid`, then `gh run list --commit <sha>`); on `cancelled`, look for
  a newer run on the same branch before reporting anything.
- **Evidence uploads never fail a build.** An artifact upload step gets `continue-on-error: true` and
  a warning in the job summary, and keeps a short retention: a full artifact quota otherwise turns
  every PR red while the build and the tests passed (an *infrastructure* red, CORE §4).
- **A required check runs on every PR.** A workflow with a `paths` filter on its `pull_request` trigger
  cannot be a required check: a PR outside the paths never gets it and waits forever. Filter inside
  the job (a scope step that ends early) instead.
- **A self-hosted runner and a public repository.** On a public repository a fork's pull request runs
  its code on the runner once a person approves the contributor's first run (GitHub's default
  `first_time_contributors`). Either the repository stays private, or both hold: fork PRs never reach
  the runner (the job's `if: github.event_name != 'pull_request' ||
  github.event.pull_request.head.repo.full_name == github.repository`), and approval is required for
  all external contributors. A job skipped by `if:` counts as a passed required check, so a fork PR is
  merged only after a person has read its code, never on CI alone. That `if:` covers `pull_request`
  only: no job on the self-hosted runner may run on `pull_request_target`, `issue_comment` or
  `workflow_run` and check out a PR's head — those run with the base repository's rights and are the
  usual way a fork's code reaches a runner. A change of visibility re-runs the
  `branch-protection` and `state-private` checks (ONE-TIME).

## Checks
- `scripts/check-contract.sh|.ps1 <contract>` — a contract against CONTRACT.md (CORE §4): ERROR blocks
  delegation, WARN goes into the brief. `scripts/check-core.sh|.ps1 [repo]` — the core's links and §
  references (CORE §10), and the feature map [FEATURES.md](FEATURES.md) in sync with the files. Windows: `powershell -File scripts\check-core.ps1`.
  `scripts/check-scripts.sh|.ps1 [folder ...]` — every `.sh` (`bash -n`) and `.ps1` (PowerShell's own
  parser; under `powershell` for 5.1's rules) parses; `<file>:<line>: <message>` per error, nothing
  installed. A language with no shell on the machine is listed as skipped, never as passed. Run it on
  the project's coordination scripts too (CORE §12a, UPDATE-CORE). A project script that needs
  PowerShell 7 says so on its first line, `#Requires -Version 7`: 5.1 then refuses it with a clear
  message instead of a parse error, and check-scripts parses it with `pwsh` (skipped where there is
  none). On one machine the `.sh` and the `.ps1` give the same verdict: both use Windows PowerShell 5.1
  where it exists.
  `scripts/selftest.sh|.ps1 scripts|env|hooks|hookcheck|prepare|verify` (in a project: the state repository, evidence kept)
  and `sandbox|clean` (the core itself: a sandbox at a fixed path, which `clean --keep` resets to its
  first commit and keeps, so the owner trusts its repo once; a full `clean` removes it) — the scripted steps of the self-test
  ([procedures/SELFTEST.md](procedures/SELFTEST.md)); `PASS` / `FAIL` / `SKIP` lines, exit 1 on a FAIL. The
  `.ps1` runs the `.ps1` scripts under every PowerShell on the machine (5.1 and pwsh).

## Usage and limits
- **Model ladder** (CORE §7): `claude auth status` gives the login method (`authMethod`) and
  `subscriptionType` (e.g. `max`; seen on 2.1.296, not in the docs, so a hint); the status line gives
  the 5-hour and weekly use on Pro / Max only, with no per-model entry. Probe a model with
  `claude -p --model <id> "ok" --output-format json`: a non-zero exit or an error result means not
  available. A probe loads the full system prompt and tools, so it is not free (on Arx at list price:
  Fable $0.47, Opus $0.18, Sonnet $0.09, Haiku $0.005). A model's own limit shows only as a message ("You've hit your Opus
  limit"); switching family keeps working. List prices: the Claude pricing page, copied into BINDINGS.
  [model-config](https://code.claude.com/docs/en/model-config.md)
- **Tokens and cost per run** (CORE §7 run log): `scripts/session-tokens.sh <session-id>` (Windows:
  `scripts/session-tokens.ps1`; the 8-character id that `claude --bg` and `claude agents` print works
  as a prefix) when the run ends. It prints one line per model and a `total` line summed from the
  transcript in `~/.claude/projects/`, subagents included — input and cache counts exact, **output a
  lower bound** (the transcript keeps the count from before a message finished) — and a `cost` line:
  the status line's `cost.total_cost_usd` for that session (cumulative, at API list price; on a
  subscription for comparing runs; needs the status line installed). The status JSON's
  `context_window.total_input_tokens` / `total_output_tokens` are the **last request's** usage, not the
  session's (measured on Arx), so tokens always come from the transcript. No `cost` line → the tokens
  per model times the list prices, `cache_write` at the **1-hour** price (Claude Code writes 1-hour
  cache entries, `prompt_cache.ttl: "1h"` in the status JSON; on Arx this matched the status cost to
  the cent). **A subagent** (the Agent tool) has no session id and no status file: pass the `agentId`
  its result gives (or a unique prefix) — session-tokens reads `<parent>/subagents/agent-<id>.jsonl`
  and prints its own tokens per model, never a `cost` line; its cost is those tokens at list price. It
  is already inside its parent session's lines and cost, so its run-log row says `in <parent>` and a
  sum of the project's spend counts it once. **Time per run** (CORE §7a): for one session or subagent
  the last line is `time` and, after a tab, `wall=<m>m active=<m>m start=<UTC> end=<UTC>`, from the timestamps of every
  record in the files it counts (the transcript and its subagents', as one set): wall = the last minus
  the first; active = wall minus every gap over 5 minutes between two consecutive records (waiting for
  a limit, for an answer, a sleeping machine), so a background subagent working while its parent is
  quiet is active time. A gap inside a tool call — from a `tool_use` to its own `tool_result`, matched
  by id, parallel calls overlapping — is work up to 30 minutes and idle beyond that (a long build,
  `gh pr checks --watch`; the Bash tool stops at 10 minutes, and a subagent's own work is counted through
  its transcript, so a longer span is waiting, a night included). A call of a tool that asks a person
  (`AskUserQuestion`, or any tool whose name ends in it) is never active: its span is the owner's time,
  at any length. A gap after a result keeps the 5-minute rule. Minutes rounded to the nearest, a half up;
  `start` and `end` to the second, UTC. No line when no record has a timestamp, and none with `--since`
  or `--prune`. **The order** when a run ends: read its cost (a failed read retried once with the full
  command, never left as `n/a`), then delete that worker's `sessions/<id>.json` (the `cost` line comes
  from it), then `claude stop` / `claude rm` (session-tokens still reads a removed session's
  transcript, but not its cost line). The status line writes a file for every
  session on the machine, other projects' too, so at every session start run `session-tokens.sh --prune`
  / `session-tokens.ps1 -Prune` (deletes files older than 7 × 24 hours, and the status line's
  `coordinator/statusline.*.tmp` older than an hour, left when it was killed mid-write; on Windows only
  the `-Prune` form reaches the script through `-File`).
- **A run cut by a usage limit** (a 429 "You've hit your weekly limit · resets …", a session shown
  `blocked`): pause until the status line's `resets_at` (CORE §9), then for each blocked session
  `claude respawn <id>` **and** a one-line SendMessage ("the limit has reset, continue") —
  respawn alone brings it back idle and still blocked (seen on 2.1.296). The report notes the pause.
- **Spend since a reset, account-wide** (CORE §7a): `session-tokens.sh --since <UTC time>` /
  `session-tokens.ps1 -Since <UTC time>` — the same per-model lines over every transcript on the
  machine, each message once, counted by its own timestamp (a session that crosses the reset is
  split). The limits are per account, so other projects' and ad-hoc sessions' spend counts too. The
  status line's `resets_at` is the window's **next** reset (Unix seconds), so the window began at
  `resets_at` minus its length — 5 hours for `five_hour`, 7 days for `seven_day`; `run-stats --limits`
  prints that start as `since`. Pass it as `YYYY-MM-DDTHH:MM:SSZ` or as Unix seconds (`--since 1791219600`);
  a time with another offset (`+02:00`) is refused, not read as UTC.
  An ambiguous prefix (of a transcript or a status file) fails and lists session ids only, never
  project folders. A model cannot see its own counter (the status line is drawn
  by the CLI), so a worker's self-reported tokens are a guess; but every session knows its own full id
  (`CLAUDE_CODE_SESSION_ID` in its environment), so `session-tokens "$CLAUDE_CODE_SESSION_ID"` (PowerShell:
  `$env:CLAUDE_CODE_SESSION_ID`) prints its own tokens, cost and time — a lead reads itself that way.
- **Where sessions lose money, time, quality or stability** (CORE §7a, the weekly retro's input):
  `scripts/session-insights.sh <session-id | prefix | agentId | transcript.jsonl>` or `--since <UTC time
  | Unix seconds>` (`session-insights.ps1 <id>` / `-Since`; `--detail` / `-Detail`), the same lookup
  as session-tokens: a session is its transcript and its subagents', `--since` every transcript on the
  machine, each record by its own timestamp. It only reads and prints; nothing is sent anywhere. With
  `--since`, the retro's filters: `--until <time>` (`-Until`: records before it only); `--skip-tests`
  (`-SkipTests`: no probe or self-test session — a name with `probe`, `selftest` or `self-test` as a word
  before its first colon, a task `#st<n>`, or a first cwd inside a `coordinator-selftest` folder; a
  product task whose title only mentions a self-test stays); `--project <folder>` (`-Project`: only the
  sessions whose first cwd is the folder or inside it, `\` read as `/`, case ignored, `C:/x` as `/c/x`) —
  a session judged by its last name (`customTitle` / `agentName`) and its first `cwd`, a subagent by its
  parent's. Lines, tab-separated, one kind per line, no header; nothing for a session without messages:
  - `block <reason> count= changed= retried= around= stopped=` — per safety-guard reason (the text
    after `Blocked by safety-guard: ` up to `. If this is a false positive`, a path in parentheses as
    `(<path>)`, so no folder leaves the machine) and `deny rule` (a `Permission to use … has been
    denied` result). Only results with `is_error` that start `PreToolUse:` (the hook error) or with the
    message count, never a test printing the message; probe and self-test sessions block on purpose,
    so the retro filters them out. Then the same transcript's **next tool call**: `retried` — the same tool
    with the same command (else `file_path`, else input); `around` — another call naming one of the
    blocked call's targets: its `file_path`, and in its command `main`, `master` and the words holding a
    `/` or `\` with 2 letters or digits (`/dev/…` aside), plus the branch of `push while on <b>`, found as
    a whole word, case and `\` against `/` ignored; `stopped` — an `end_turn` or the transcript's end
    comes first; `changed` — anything else. `around` is a signal, not proof: a correct next step can
    name the same path (a `cd` into it, the cleanup script with the worktree), and a way around through a
    variable or another spelling is `changed` — so the retro treats `around` as worth a look, not as a
    finding.
  - `refusal <source> count= changed= retried= around= stopped=` — the other refusals, with the same
    next-call reading as blocks: `hook <script>` (another hook's `PreToolUse:` error, named by the
    script in its command, folders left out; `hook` when the command is not shown), `classifier` (the
    auto-mode classifier), `safety check` (Claude Code's built-in check), `user` (the user said no to a
    permission), `other` (any other rejected permission). An interrupt is neither a refusal nor an error.
  - `tool_error <tool> count= repeated= exit_only=` — results with `is_error` that are no block, refusal
    or interrupt; `repeated` — the tool's next call had the same command (else the same input) and
    failed again. A command exiting non-zero is an error to the transcript; when its whole text is
    `Exit code <n>` (`grep` without a match, a `diff` that differs, a test returning false) it goes to
    `exit_only`, not `count`, so `count` is failures that showed output — a failing command that prints
    is still in `count`.
  - `waiting minutes= calls=` — calls over 2 minutes from `tool_use` to `tool_result` that waited on a
    person: a permission the user decided (the result's `permissionDecision` with a `source` starting
    `user`: `user_temporary`, `user_reject`, …) or a tool named `*AskUserQuestion`. The span includes the
    tool's own run after the answer, and transcripts written before Claude Code recorded
    `permissionDecision` show only the AskUserQuestion waits; a prompt answered within 2 minutes is not
    counted.
  - `cache write= read= rewrites=` — tokens, each message once (as session-tokens); a rewrite is a
    message writing over half its input (input + cache write + cache read) to the cache: a context paid
    again after a pause past the cache's lifetime or a restart. A transcript's first message writes its
    context for the first time and is not one; a rewrite after a compaction is one.
  - `reread files= reads=` — files the Read tool read 3 or more times in one transcript (a subagent's
    reads are its own context) and those reads, any offset or limit. No file names: `--detail` adds
    `reread_file <path> reads=<n>` lines for local use — **that output never leaves the machine**
    (it is not pasted into an issue, a report or the state repository).
  - `turns assistant= tool_calls=` — distinct messages and tool calls.
  Each transcript is read in order on its own (parallel calls: the next call is the next `tool_use`
  record after the result); a result whose call is not in the files read (or before `--since`) is
  skipped, and so is a line that is no record (a malformed or cut line). Exit 1 when no transcript is
  found or a prefix is ambiguous, 2 on a usage error.
- **The weekly retro** ([procedures/RETRO.md](procedures/RETRO.md)): `scripts/retro.sh <RUNS.tsv> [--week
  <YYYY-MM-DD>] [--project <root>] [--journal <LOG.md>] [--escapes <ESCAPES.tsv>] [--no-insights]`
  (`retro.ps1 <RUNS.tsv> -Week … -Project … -Journal … -Escapes … -NoInsights`). The week is Monday to
  Sunday UTC holding `--week` (default: the last complete week), against the 7 days before it; the
  project root defaults to the folder above the run log's, the journal and escapes to `LOG.md` and
  `ESCAPES.tsv` next to it. A task is its rows as in run-stats, in the week of its latest row date; rows of
  a task `st<n>` or `0`, or a kind or role naming probe or self-test, are left out; a task-less row is the
  coordinator's own cost. The transcripts: `session-insights --since <week> --until <its end> --skip-tests
  --project <root>` per week. It prints, tab-separated, `retro` with the weeks, `axis measure week
  previous` and a line per measure — *cost*: `tasks merged median_per_task total coordinator
  per_merged_task`; *speed*: `ready_median work_median owner_wait_median owner_wait_open` (the owner wait
  apart); *quality*: `rework_rate escalated_rate failed_rate escapes escapes_per_10_merged`;
  *predictability*: per cost, work and ready `_forecasts _in_range _ratio_median` (a forecast: 3 or more
  earlier tasks of the kind and model, the last 10 before the task's first row, its range run-stats'
  25th–75th percentile, min–max under 4); *stability*: `failed_runs guard_blocks deny_rule_blocks
  guard_around guard_false_positives guard_errors refusals tool_errors tool_calls tool_error_rate
  cache_rewrites cache_rewrites_per_task waiting_minutes rereads` — then `kind name tasks rework escalated
  failed` per kind of the week and the week's `block` / `refusal` lines. Money to the cent, minutes and
  percents whole, rounded half up from integers, the same from the .sh and the .ps1; `—` is too little
  data (under 3 values; under 100 tool calls; no transcripts, journal or escapes file). `--public --id
  <12 hex>` (`-Public -Id`) prints instead the anonymous Markdown body: a fixed template, numbers and the
  allowlist only (the core's kinds or `other`, the guard's reasons and refusal sources as fixed keys, the
  id, the dates), checked before it is printed. `--check-public <file>` (`-CheckPublic`) checks a summary
  body — it fails on a line outside the template, a cell outside the allowlist, a `/` or `\`, or the
  folder name of `--project`; `--check-proposal <file>` (`-CheckProposal`) checks a proposal body against
  RETRO's template (its core file a file of the core, its two text lines with no path outside the core,
  link, address or task number); `--new-id` (`-NewId`) prints a random id. Exit 1 when a file cannot be
  read or a check fails, 2 on a usage error.
- **Forecast numbers** (CORE §7a): `scripts/run-stats.sh <RUNS.tsv>` (Windows: `scripts/run-stats.ps1`)
  prints a header and one tab-separated line per kind and model — `kind model cost_n cost_median
  cost_low cost_high time_n time_median time_low time_high ready_n ready_median ready_low ready_high` —
  over **tasks**: the rows whose task
  number agrees before its first dot (`37`, `37.1`, `37.2`) are one task, its cost and time the sums of
  the values its rows have (cost in USD, `active` in minutes; empty, `-`, `n/a` or `in <parent>` are no
  value, and a subagent's row, cost `in <parent>`, adds no time — it is inside its parent's); a task
  none of whose rows has a value for a measure is left out of that measure only; rows from before the
  time columns count for cost only. A task's kind and model are its lead row's, else its first worker
  row's, else its first row's; an empty or `-` task (the coordinator's own daily line) is no task. Per
  pair and measure the last 10 tasks with a value count (ordered by their last row). Median: the
  mean of the two middle values for an even count; low / high: the 25th and 75th percentile by nearest
  rank (the value at rank ⌈p·n/100⌉) from 4 tasks on, min and max under 4; cost to the cent, time to
  the minute, rounded half up; a pair with no values shows `0` and `-`. The `ready_*` columns come
  from the **task rows** (role `task`, CORE §7) alone: per task its last task row's `wall` (time to
  ready), under that row's kind and model, the same last-10 and percentile rules; task rows add nothing
  to cost or time, which their runs already hold. `--kind <k> --model <m>`
  (`-Kind`, `-Model`) prints that pair's line only — a contract's `budget.cost` and `budget.time`, and the
  ready forecast beside them. `--per-run` (`-PerRun`) groups single rows by kind, role and model instead,
  for diagnosis, without task rows and without the ready columns.
  Columns are read by the header line (first field `date`), else in CORE §7's order. Exit 1 when the
  file cannot be read, 2 on a usage error.
- **A task's time to ready and owner wait** (CORE §7a): `scripts/run-stats.sh <RUNS.tsv> --task <n>
  --pr-json <file> --waits <file>` (`run-stats.ps1 <RUNS.tsv> -Task <n> -PrJson <file> -Waits <file>`)
  prints the task row to append to `RUNS.tsv` when the task merges: `gh pr view <PR> --json
  statusCheckRollup,mergedAt,createdAt > <file>` (or `--pr-json -` from a pipe; `-PrJson:-` in
  Windows PowerShell 5.1), and the owner questions that held the task up, from the journal, one
  `<asked> <answered>` per line in UTC (`2026-10-06T08:20:00Z 2026-10-06T08:35:00Z`; `#` comments). It
  takes the task's rows (`37`, `37.1`, … — task rows aside): `start` the earliest start, `active` the
  summed work (a subagent's row aside), kind and model as above; ready is the later of the last
  approving verifier run's start + wall and the moment the checks were all green — per check (type,
  workflow, name) its run started last counts, so a green rerun replaces a red run, and the last
  `completedAt` of those; a check not green (red, running) or verifier rows none of which approved:
  not ready, exit 1; no checks, or no `--pr-json`: the verifier alone. `wall` = ready − start − the
  owner waits inside that span (overlaps once); `wait` = merge − ready + those waits; unmerged:
  result `ready`, `wait` `<m>+` (open — append the merged row later; the last one counts). Minutes
  rounded half up from exact seconds; the row in the file's header order, missing names (`wait` in an
  older file) appended in CORE §7's order. Exit 1 also when the task has no rows or no start, or a wait
  line is no pair of UTC times.
- **Limits: percent per dollar and the block's fit** (CORE §7a): `scripts/run-stats.sh --limits`
  (`run-stats.ps1 -Limits`, the options in each shell's form: `-Spend5h`, `-CapWeek`, …) does the
  limit arithmetic, never by hand. Inputs, all optional: `--status <file>` (default
  `<config>/coordinator/statusline.json`, `<config>` = `$CLAUDE_CONFIG_DIR` or `~/.claude`);
  `--spend-5h` / `--spend-week <file>` — what `session-tokens --since <since>` printed for that window
  (`-` reads stdin, for one of them; Windows PowerShell 5.1 takes it only as `-Spend5h:-`); `--prices
  <file>`, needed with a spend — the ladder's list prices from BINDINGS *Models*, one model per line,
  `<model id> <input> <output> <cache read> <cache write>` in USD per million tokens (cache write at the
  1-hour price; `$` and ` / ` allowed, `#` comments; e.g. `claude-opus-5-5 $5 / $25 / $0.50 / $10`), then
  `not-weekly` for a model with its own limit whose spend does not count toward the weekly one (assumed:
  every model, an own-limit one too, spends the 5-hour window — not measured — so `five_hour` sums them
  all); the project keeps it as `coordinator/prices.txt` (one-time step `prices-file`); a spend
  model takes its own id's line, else the longest id it starts with, else exit 1; `--prev-5h` /
  `--prev-week <% per $>` (the last window's ratio); `--cap-5h` / `--cap-week <%>` (the project's caps,
  §9); `--block <USD>` (the block's estimate). Two steps: first without a spend, for each window's
  `since`; then `session-tokens --since <since>` per window into a file, and again with the spends. It
  prints a header and a tab-separated line per window, `window used since resets cost ratio basis left
  left_cap block fit`: used percent (one decimal); the window's start and its reset (UTC); the account's
  list-price cost since the start (to the cent; `seven_day` without `not-weekly` models); the ratio in
  percent per dollar (four decimals) and its basis — `trusted` (the window has risen ≥ 10 points: used
  over cost), `previous` (under 10, `--prev-*` given), `guess` (under 10: used over cost), `-` (none); the
  dollars left before 100% and before the cap (rounded down); the block's percent and `fits` / `does
  not fit` within the cap (100% without one). Fixed-point arithmetic, so the `.sh` and the `.ps1` print
  the same. A window missing from the JSON prints `-`; a `resets_at` already passed means the window has
  reset (used 0, no cost, the ratio only from `--prev-*`). Exit 1 when a file cannot be read, the JSON has
  no `rate_limits` (an API key, an older Claude Code: budget by cost), a price line is malformed or a
  spend model has no price; 2 on a usage error.
- Background sessions draw their status line without being opened. The status line command receives JSON with `rate_limits.five_hour.used_percentage`,
  `rate_limits.seven_day.used_percentage` and `resets_at` (claude.ai Pro / Max only, after the first
  response). `scripts/statusline.ps1` (Windows) / `scripts/statusline.sh` (macOS / Linux, needs `jq`)
  save it to `~/.claude/coordinator/statusline.json` (the last session to draw) and to
  `~/.claude/coordinator/sessions/<session_id>.json` (one per session) for the coordinator to read, and print
  `Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%`. Both write each file (`statusline.json` and
  the session's copy) to `statusline.<pid>.tmp` and move it over, so neither is ever seen half-written
  or empty; on Windows, when another status line or a reader holds the file, the move fails (three
  tries, 20 ms apart), the old file stays for that tick and the temp file is removed.
  [statusline](https://code.claude.com/docs/en/statusline.md)
- **Installing it** (only on the owner's yes in the init quiz, CORE §3, and only where no `statusLine`
  is set yet; replacing a project's own one is the owner's choice, and first the coordinator lists
  the project's scripts and BINDINGS rows that read the old one's files — they stop getting data
  without an error — so they become a task at once). The coordinator sees the files and can run the
  script on the same JSON, but not the window: only the owner sees the drawn line.
  Then: add to the user settings (`~/.claude/settings.json`, with the Edit tool — the owner
  approves the write) the script's absolute path in the core copy (`/ABSOLUTE/PATH` = `<project>/coordinator/core`;
  the user settings serve every project, so one project's copy is used for all):
  Windows `"statusLine": {"type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"C:/ABSOLUTE/PATH/scripts/statusline.ps1\""}`
  (`powershell` instead of `pwsh` where PowerShell 7 is missing); macOS / Linux
  `"statusLine": {"type": "command", "command": "bash /ABSOLUTE/PATH/scripts/statusline.sh"}`. It
  appears after the next response.
- API-key setups have no such data: budget by cost (`--max-budget-usd` on headless jobs) instead.

## Platform notes
- macOS: the background-session host needs the *Files and Folders* and *Local Network* permissions.
- Notifications: `osascript` (macOS), `notify-send` (Linux), PowerShell toast (Windows).
- Windows: Claude Code runs Bash tools through Git Bash; PowerShell 7 is a separate tool.
- "Could not resolve authentication method" on dispatch → `claude daemon stop --any --keep-workers`, then
  check the login.

## New machine — safe start checklist
Run in this order; the first work is a **dry run** (CORE §12a).
1. `claude --version` meets the messaging minimum above; `gh auth status` (or the host's CLI) logged in.
2. The owner trusts the project folder (and accepts any one-time consent) — the owner's own step.
3. **Worker safety file** from [settings.example.json](settings.example.json) (Windows:
   [settings.example.windows.json](settings.example.windows.json)) with absolute paths — the core copy's
   for the hook, the project root for `COORD_PROTECTED_ROOT` (*Safety*) — (passed to every
   worker by `start-worker.sh --safety` / `start-worker.ps1 -Safety`). **The coordinator's own settings** (its session or the
   user settings): the status line if the owner wants it (CORE §3, *Installing it* above) and
   `crossSessionInbound: "accept"`.
   Secrets net: enable the code host's push protection / secret scanning (or a `gitleaks protect`
   pre-commit) — a leaked token on the host cannot be rolled back, only rotated.
4. Make the scripts executable: `chmod +x scripts/*.sh scripts/hooks/*.sh` (macOS / Linux).
5. Test the hook: `scripts/hooks/safety-guard.sh --self-test` (Windows: `powershell -NoProfile
   -ExecutionPolicy Bypass -File scripts\hooks\safety-guard.ps1 -SelfTest`) → `safety-guard: OK`.
   Windows: start-worker needs the native `claude.exe`; an npm `claude.cmd` cuts a multi-line brief.
6. Branch protection on the code host is on (or the owner records why not).
7. Initialize (CORE §2 — the one start sequence): context of running sessions and PRs, open questions,
   the init quiz, `PROJECT.md` / `BINDINGS.md`, the access list and project map, the platform row, the MCP
   tool check.
8. Dry run → the owner approves → wait for the owner's first task or batch command; a tick only where autopilot is on (swarm, CORE §3).

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
  role file's body at the top of its prompt and the role's model. Check the frontmatter fields (`name`,
  `description`, `tools`, `model`) against the sub-agents docs in the dry run.
- **Lessons:** a session's message address can change after `respawn` — list sessions again and use the
  bare name; idle sessions may exit — `respawn` them when their turn comes; remove a session with
  `claude rm` as its own command (some guards block compound removals).

## Working copies
- **The core's way:** `scripts/start-worker` creates `.claude/worktrees/<branch>` with `git worktree add`
  (branch `<issue>-<type>-<slug>`) and starts the session for it (from the repository root, *Directory and
  trust*) with `worktree.bgIsolation: "none"`, so
  Claude Code does not add a second copy; the worktrees' folder is kept out of the project's git by a
  local `.git/info/exclude` line (INIT 3.4). Its built-in alternative (`claude --worktree <name>`, branch
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
  `git branch` with any delete flag, `git update-ref -d`), and removing `/`, a drive, home or a
  worktree by hand (`rm` / `Remove-Item` / `rd /s` in their recursive forms, `find … -delete`, a
  `Get-ChildItem` / `ls` piped into `Remove-Item -Recurse`, `git worktree remove --force`; a drive also
  as `/c`, `/mnt/c`, `/cygdrive/c`, home also written out in its Windows or Git Bash form; `.`, `*` and
  other relative targets count from the folder a `cd` led to). It parses
  the command like a shell: line continuations are joined, separators inside quotes (a commit
  message, a PR body) do not split, `{ … }` groups and PowerShell script blocks split like `( … )`,
  wrappers are skipped with their options (`sudo -E`, `env -i`, `timeout 30`, `nice -n 5`, `stdbuf
  -oL`, `builtin`, `noglob`, `time`, `nohup`, `exec`), `$(…)`, `bash -c` / `pwsh -Command` (or a prefix
  such as `-Com`) and a heredoc fed to a shell
  are checked as commands of their own. Work-branch operations (push, force-push, rebase, amend,
  reset, deleting work branches) and tag-only pushes pass. Exit code 2 blocks and
  shows the reason. Input it cannot read (not a JSON object) blocks; a BOM before the object is dropped;
  only `tool_input`'s own `command` is read. A project's own patterns (`.claude/coordinator-deny.txt`,
  one regex per line, trimmed, CRLF or LF) block what they match; a pattern that cannot be read blocks
  every call (`project rule cannot be read: <line>`) until the file is fixed.
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
  Hooks see only shell tools — **MCP tools are covered by deny rules only** (the settings examples
  deny the GitHub MCP write tools; rename them to the server name connected on the machine and add
  any other server that can write to a protected branch). Whether hooks run in
  `bypassPermissions` *(unconfirmed)*. [hooks](https://code.claude.com/docs/en/hooks.md)
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
  repositories with stub `claude` and `gh`; the real `claude` is never called).

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
  and `sandbox|clean` (the core itself) — the scripted steps of the self-test
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
  sum of the project's spend counts it once. **The order** when a run ends: read its cost (a failed read retried once with the full
  command, never left as `n/a`), then delete that worker's `sessions/<id>.json` (the `cost` line comes
  from it), then `claude stop` / `claude rm` (session-tokens still reads a removed session's
  transcript, but not its cost line). The status line writes a file for every
  session on the machine, other projects' too, so at every session start run `session-tokens.sh --prune`
  / `session-tokens.ps1 -Prune` (deletes files older than 7 days; on Windows only the `-Prune` form
  reaches the script through `-File`).
- **A run cut by a usage limit** (a 429 "You've hit your weekly limit · resets …", a session shown
  `blocked`): pause until the status line's `resets_at` (CORE §9), then for each blocked session
  `claude respawn <id>` **and** a one-line SendMessage ("the limit has reset, continue") —
  respawn alone brings it back idle and still blocked (seen on 2.1.296). The report notes the pause.
- **Spend since a reset, account-wide** (CORE §7a): `session-tokens.sh --since <UTC time>` /
  `session-tokens.ps1 -Since <UTC time>` — the same per-model lines over every transcript on the
  machine, each message once, counted by its own timestamp (a session that crosses the reset is
  split). The limits are per account, so other projects' and ad-hoc sessions' spend counts too. The
  reset time is the status line's `resets_at`. An ambiguous prefix lists session ids only, never
  project folders. A model cannot see its own counter (the status line is drawn
  by the CLI), so a worker's self-reported tokens are a guess.
- Background sessions draw their status line without being opened. The status line command receives JSON with `rate_limits.five_hour.used_percentage`,
  `rate_limits.seven_day.used_percentage` and `resets_at` (claude.ai Pro / Max only, after the first
  response). `scripts/statusline.ps1` (Windows) / `scripts/statusline.sh` (macOS / Linux, needs `jq`)
  save it to `~/.claude/coordinator/statusline.json` (the last session to draw) and to
  `~/.claude/coordinator/sessions/<session_id>.json` (one per session) for the coordinator to read, and print
  `Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%`.
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
   [settings.example.windows.json](settings.example.windows.json)) with absolute paths (passed to every
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

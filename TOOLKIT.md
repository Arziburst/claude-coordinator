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
- **The coordinator's own name** (CORE §2 step 1): `Coordinator`. Started by the owner from
  the CLI: `claude --name "Coordinator"`; in an already running session the owner can rename
  it (`/rename <name>` *(unconfirmed)*). If the coordinator cannot rename itself, it asks the owner to —
  once, at init. Every project's coordinator has this name: tell them apart by their working directory
  (`claude agents --json` *(unconfirmed field name)*).
- **Model:** `--model`. **Effort** for `--bg` *(unconfirmed)* — put the effort in the brief if no flag works.
- **Directory:** start the session from the worker's working copy (`cd` first); there is no documented
  `--cwd` *(unconfirmed)*.
- **Trust:** the folder must already be trusted, or `--bg` fails with "Workspace not trusted". Trusting a
  folder is the **owner's** step — never written into config by the coordinator.
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
  subagent then starts as that role; a background session (a worker, usually) gets the file's body at the top of its brief and its
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
  (branch `<issue>-<type>-<slug>`) and starts the session there with `worktree.bgIsolation: "none"`, so
  Claude Code does not add a second copy. Its built-in alternative (`claude --worktree <name>`, branch
  `worktree-<name>`) is not combined with it. Whether `git worktree add` into `.claude/` raises the
  protected-path prompt (*Safety*) *(unconfirmed)*: check in the dry run; if it does, set the
  worktree root outside `.claude/` in `BINDINGS.md`.
  [worktrees](https://code.claude.com/docs/en/worktrees.md)
- After merge: remove the worktree only if clean and fully pushed (CORE §8) — `scripts/cleanup-worker.sh`.

## Messages between sessions
- `ListAgents` + `SendMessage` (Claude uses them itself); `notify_when_idle: true` gives one notice when
  the worker is next idle (same machine, expires after 12 h).
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
  following `git checkout` / `switch`, `cd` / `Set-Location` and `git -C` in the same command;
  `git branch` with any delete flag, `git update-ref -d`), and removing `/`, a drive, home or a
  worktree by hand (`rm` / `Remove-Item` / `rd /s` in their recursive forms, `find … -delete`). It parses
  the command like a shell: line continuations are joined, separators inside quotes (a commit
  message, a PR body) do not split, `$(…)`, `bash -c` / `pwsh -Command` and a heredoc fed to a shell
  are checked as commands of their own. Work-branch operations (push, force-push, rebase, amend,
  reset, deleting work branches) and tag-only pushes pass. Exit code 2 blocks and
  shows the reason. **A hook that fails to run does not block** — so the settings example runs the
  hook's self-test at session start (`safety-guard.sh --self-test` / `safety-guard.ps1 -SelfTest`); a failure there means: fix before starting workers.
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
  `Read(**/.env*)` and the stack candidates (database CLIs, production deploys, MCP write tools) from
  `examples/nextjs-supabase/settings.json`.
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
  [permission-modes](https://code.claude.com/docs/en/permission-modes.md)

## Scripts
One style for every script in `scripts/`, so each runs on a bare Mac and a bare Windows machine:
- **A pair with the same behaviour and output:** `<name>.sh` for macOS / Linux and `<name>.ps1` for
  Windows. Same arguments, same messages, same exit codes; a change to one is made to the other in the
  same pull request.
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
- **Tests:** `tests/safety-guard/run.sh <hook command>` (the shared verdicts) and
  `tests/workers/run.sh sh|ps <powershell>` (start-worker / cleanup-worker against temporary
  repositories with stub `claude` and `gh`; the real `claude` is never called).

## Checks
- `scripts/check-contract.sh|.ps1 <contract>` — a contract against CONTRACT.md (CORE §4): ERROR blocks
  delegation, WARN goes into the brief. `scripts/check-core.sh|.ps1 [repo]` — the core's links and §
  references (CORE §10). Windows: `powershell -File scripts\check-core.ps1`.
  `scripts/check-scripts.sh|.ps1 [folder ...]` — every `.sh` (`bash -n`) and `.ps1` (PowerShell's own
  parser; under `powershell` for 5.1's rules) parses; `<file>:<line>: <message>` per error, nothing
  installed. A language with no shell on the machine is listed as skipped, never as passed. Run it on
  the project's coordination scripts too (CORE §12a, UPDATE-CORE).

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
  the cent). Then delete that worker's `sessions/<id>.json`; the status line writes a file for every
  session on the machine, other projects' too, so at every cycle start run `session-tokens.sh --prune`
  / `session-tokens.ps1 -Prune` (deletes files older than 7 days; on Windows only the `-Prune` form
  reaches the script through `-File`).
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
Run in this order; the first cycle is a **dry run** (CORE §12a).
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
8. Dry-run cycle → the owner approves → wait for "start a new cycle"; a tick only where autopilot is on (swarm, CORE §3).

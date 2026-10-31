# Toolkit — Claude Code mechanics for a coordinator

How a coordinator does its job with Claude Code on **any machine** (Windows, macOS, Linux). This file
tracks Claude Code features and changes with them — re-check the linked docs when something behaves
differently. Items marked *(unconfirmed)* were not stated in the docs; verify them in the dry run (CORE §12a).

## Workers: start, name, manage
- **Background session per worker:** `claude --bg --name "#<task> worker: <title>" --model <model> --permission-mode <mode> "<brief>"`
  — prints an id; `claude agents [--json]`, `claude logs <id>`, `claude attach <id>`, `claude stop <id>`,
  `claude respawn <id>`, `claude rm <id>`. `--bg` cannot be combined with `-p`.
  **Two ids** (measured on 2.1.296, Windows): these commands take the **short** job id — `id` in
  `claude agents --json`, the one `claude --bg` prints in `claude stop <id>` (so far always the first 8
  characters of `sessionId`); `claude stop` and `claude rm` refuse the full `sessionId` ("No job
  matching '<uuid>'", exit 1, the session stays listed). Only `claude --bg --resume` takes the **full**
  `sessionId` (*Pause and resume*). `claude agents --json --all` lists the stopped (`done`) sessions too.
  These commands, `--resume` and SendMessage reach **any** session on the machine, other projects'
  included: act only on sessions whose `cwd` is inside the project (CORE §1.17; the layers: *Safety*).
  [agent-view](https://code.claude.com/docs/en/agent-view.md), [cli-reference](https://code.claude.com/docs/en/cli-reference.md)
- **Name every session** (CORE §4): `--name` / `-n`; without it the name is auto-generated and the owner
  cannot tell sessions apart. The name carries the role, not the project: `#37 worker: <title>`.
- **Session or subagent, per role:** `worker` — a background session in its own working copy (named
  `#<task> worker: …`); `verifier` — a background session (`#<task> verifier: …`), or a subagent where
  `PROJECT.md` allows; `lead` — a background session (`#<task> lead: …`) in its integration branch's
  working copy, started like a worker, which itself starts its workers (`#<task>.<n> worker: …`) and
  runs tester, verifier and scout as its own subagents — a background session can start
  further background sessions (confirmed on Claude Code 2.1.296, Windows); if a version refuses, the
  lead sends its start-worker commands to the coordinator, which runs them; `researcher` — a subagent, or a session (`researcher: <topic>`) for long research;
  `scout` — a subagent only; `tester` — a subagent for a short run, else a background session
  (`#<task> tester: …`): start-worker with the worker safety file, in the task's working copy and
  branch, the worker started after its report in the same copy (start-worker reuses it). A session when
  **the coordinator's own settings hold no guard** — a subagent runs under the settings of the session
  that started it, not under the worker safety file, and the tester pushes (the self-test's
  `selftest hooks` on those files, SELFTEST step 2a, says whether they hold it) — or when **the run is
  long**: a flake's reproduction, a build or suite over about 10 minutes, a device; a subagent ends with
  its session and its cost is only a lower bound (`out>=`, #232). A lead's tester stays its subagent:
  the lead runs under the worker safety file. A subagent has no session of its own: it appears inside
  the session that started it, under its role name. **A role never silently becomes a subagent:** a
  subagent runs without the role's safety file and without the MCP servers its session would have; when
  background sessions cannot start (a new one crashes before init — `EPERM`, its job's state.json
  `failed` — even when start-worker reported it started; the daemon fails), stop and ask the
  owner (#265). macOS: after Full Disk Access (TCC) changes, the running `claude` daemon keeps the old
  state and new background sessions crash with `EPERM`: restart the `claude` client that started it,
  then `claude daemon stop --any --keep-workers` (running sessions survive); the next `claude --bg`
  starts a fresh daemon (measured on the reporter's machine, #265).
- **The coordinator's own name** (CORE §2 step 1): the coordinator name in `PROJECT.md` *Settings*,
  `<Project> Coordinator` by default (INIT 3.1, question 10). It must contain the English word
  `Coordinator`: the roles' fallback looks for it when a report address fails. Several projects on one
  machine each have a coordinator, and a bare name shared by two is ambiguous for SendMessage, so the
  project's short name goes in front. Started by the owner from the CLI: `claude --name "<name>"`; in a
  running session the owner types `/rename <name>` (or Ctrl+R in agent view) — a session cannot rename
  itself, and no CLI command renames a running one (`claude --bg --resume <id> --name …` starts a
  copy). `claude agents --json` shows each session's `name`, `cwd`, `id` and `sessionId`; only the name
  works as a SendMessage address, and only the name survives a `claude respawn` (2.1.296).
- **Model:** `--model`. **Effort:** `--effort low|medium|high|xhigh|max` (measured: a `--bg` session's
  transcript records it), passed by start-worker's `--effort` / `-Effort`; without it a session runs at
  the user's default effort for its model (#211).
- **After a compaction** (CORE §1.15): a summary of the conversation replaces it, and loses rules and
  state (measured: a session re-ran commands it had run). The `SessionStart` hook with matcher `compact`
  (`scripts/hooks/after-compact.sh worker` / `coordinator`, Windows `.ps1`) then puts one instruction
  into the context — re-read the job's files in full from disk before the next step: a worker or lead
  the brief start-worker kept by its session id (`<config>/coordinator/briefs/<sessionId>.md`), the
  coordinator CORE.md (§1 first, then the event table of §4), PROJECT.md, BINDINGS.md and LOG.md's open
  questions. It prints JSON `additionalContext`: plain hook output never reaches the model. The worker variant is in the
  settings examples, the coordinator variant goes in its own settings (one-time step
  `after-compact-hook`) — the project's `.claude/settings.json` too: workers launched from the root
  load it, and it stays silent in a session with a kept brief or working in a worktree (#217). The
  compaction threshold stays Claude Code's default.
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
  `description`, `tools`, `model`) against the sub-agents docs in the dry run. `assistant`
  ([roles/assistant.md](roles/assistant.md)) is installed the same way but runs only as a background
  session (`assistant: <name>`, *Assistants*), never as a subagent.
- **Lessons:** a session's message address can change after `respawn` — list sessions again and use the
  bare name; a background session idle with nothing running may exit (`done`, unreachable by
  SendMessage; 2.1.296) — a lead or a worker that still expects a message keeps a background wait
  running (roles/lead.md step 3, roles/worker.md step 3), one gone `done` is resumed (*Pause and
  resume*); remove a session with
  `claude rm` as its own command (some guards block compound removals).
- **Pause and resume a session** (a core update — UPDATE-CORE steps 4 and 6 —, the owner's request, a cap — CORE §9; measured on
  2.1.296): a session that only has to wait is told to finish its step, commit, push, report and go idle;
  a SendMessage ("continue") wakes it. To stop it outright, first record its **full** session id
  (`sessionId` in `claude agents --json` — a stopped session is listed only with `--all`), then stop it
  by its **short** id: `claude stop <id>` (`id` in the same listing; stop and rm refuse the full id,
  *Workers*). Resume takes the other one: `claude --bg --resume <full session id> "<message>"`, from any **trusted** folder (an
  untrusted one is refused: "Workspace not trusted"; a session not stopped but still idle in the
  background is not resumed but copied under a new id — stop it first): the same id,
  worktree, name, model, permission mode, settings (the guard) and history — its watch-list line stays
  (the watcher started again if it ended), a subscription is renewed (SendMessage `notify_when_idle`) only
  where one is used (*Messages between sessions*), and its cost read by the same id. Never a short id (it starts a
  **copy** under a new id in the current folder, without the name: in the owner's working copy, that is a
  session working there) and never `claude resume <id>` (no such command — the id becomes a new
  session's prompt). After a pause over an hour the prompt cache is gone and the resumed session pays its
  whole history again: for a long session a fresh worker on the pushed branch with a short note may cost
  less. The same holds without a pause: a fix round may go to a fresh worker on the pushed branch with a
  short note when a session's context has grown long, since each turn re-reads it (CORE §4 step 5,
  #292). A lead pauses and resumes its own workers the same way; a lead gone `done` while its workers
  run is resumed by the coordinator the same way, with the worker's report that fell back to it as the
  message. A resume under a new job deletes the old job folder (`$CLAUDE_JOB_DIR/tmp`), so nothing
  durable lives there: a lead's notes go in its notes folder beside its worktree (`<its worktree>.lead/`), the coordinator's contracts and
  briefs in the state repository (`coordinator/`). `claude respawn` is not a resume: it
  restarts a running session on a new Claude binary (and a usage-limit block, *Usage*).

## Working copies
- **The core's way:** `scripts/start-worker` creates `.claude/worktrees/<branch>` with `git worktree add`
  (branch `<issue>-<type>-<slug>`) and starts the session for it (from the repository root, *Directory and
  trust*) with `worktree.bgIsolation: "none"`, so
  Claude Code does not add a second copy; the worktrees' folder is kept out of the project's git by a
  local `.git/info/exclude` line (INIT 3.4), and an older lead's notes in `<worktree>/.lead/` by another;
  a lead's notes now live beside its worktree, in `<worktree>.lead/` inside that excluded folder
  (start-worker makes it and names it in the lead's brief, cleanup-worker removes it with the worktree).
  The coordinator's own session needs the same setting when it runs in the background in the isolating
  mode (reported on 2.1.310: two coordinators on the same version were never refused, and one's
  system prompt says it works in place — so it seems to depend on how the session was started, not
  the version; not proven): one-time step `coordinator-bg-isolation` (#283).
  Before anything is created (`--dry-run` too) it runs check-contract (CORE §4) on `--contract <file>` /
  `-Contract <file>` or, for a worker or a lead, on the contract in the brief (a block after a `---`
  line, to the next one or the brief's end, holding any key check-contract requires): an ERROR refuses the start with check-contract's lines, WARNs
  are printed, no contract found is one notice line and the start goes on. `--contract` / `-Contract` only
  checks a contract: the session reads the brief alone, so the contract's text goes into the brief file;
  a `--contract` whose `id:` and `title:` lines are both absent from the brief prints one WARN line saying
  so, and the start goes on (`--dry-run` too; the brief is never changed, #331). A worker whose contract has
  `tests_first: yes` is refused there too (CORE §4 step 3, #276) unless it gets the tester's tests:
  `--tester-commit <sha>` / `-TesterCommit` (a commit that is the start point or an ancestor of it — a
  reused worktree's HEAD, else the branch, else the base) or `--tester-tests <path>` / `-TesterTests`
  (an existing file or folder, a lead's case) — one of them, both together are refused; it then prints
  one line naming them. A lead is refused there too when its contract has `tests_first: yes` or it is
  given `--tester-commit` / `--tester-tests` (a lead's task gets no task-level tester: its contract says
  `tests_first: no - the lead runs the tester per sub-contract`, roles/lead.md step 3, #289). `tests_first` comes from check-contract itself (`--field tests_first`, *Checks*):
  its contract block (the front matter, or a top-level `contract:`), never from the rest of the file. Its built-in alternative (`claude --worktree <name>`, branch
  `worktree-<name>`) is not combined with it. Whether `git worktree add` into `.claude/` raises the
  protected-path prompt (*Safety*) *(unconfirmed)*: check in the dry run; if it does, set the
  worktree root outside `.claude/` in `BINDINGS.md` and name it in `PROJECT.md` *Settings* *Worktree roots*
  (one-time step `worktree-roots`), so the retro counts the sessions started there.
  [worktrees](https://code.claude.com/docs/en/worktrees.md)
- **A big brief through a file** (#291): Windows cuts a command line at 32 767 characters, and a brief
  that long once failed a start after the worktree and branch existed. start-worker decides by the size
  of the full launch text (the first line, the report line, the role, the brief) before anything is
  created (`--dry-run` too, which says which way it would go): up to **24 000 characters** it goes on the
  command line as before; above it, start-worker writes that text to
  `<config>/coordinator/briefs/launch-<branch>-<time>-<pid>.md` (beside the kept briefs, pruned with them
  after 14 days; `<config>` = `CLAUDE_CONFIG_DIR`, else `~/.claude`), prints one `brief through a file:`
  line naming it, and the session's first message is one short instruction: read that file in full with
  the Read tool before anything else, then follow it as the brief. The kept brief for after a compaction
  still holds the full launch text. A launch that fails anyway (claude `--bg` exits non-zero) exits 1 with
  a line naming what was created (the worktree, the branch) and cleanup-worker to clean it.
- After merge: remove the worktree only if clean and fully pushed (CORE §8) — `scripts/cleanup-worker.sh`;
  with `--session`, first `claude stop <id>`, read its spend (session-tokens: the stop wrote its totals)
  and delete its status file (*Usage*) — cleanup-worker then stops (a no-op) and removes it.
  A worker's worktree that cleanup-worker leaves as NOT CLEAN only for untracked files: list them to
  the owner, never remove them yourself and never `--force` (they may be work that never reached the
  PR). A detached scratch worktree (a verifier reading another commit) is different — it holds only
  that run's artefacts: `git -C <it> clean -ffdx`, then `git worktree remove <it>` (roles/verifier.md).
  `--session` takes the short id or the full `sessionId` (mapped to its short id through `claude agents
  --json --all`, else its first 8 characters); a session still listed after `claude rm` is reported as
  `SESSION KEPT: <id> (claude rm failed: <its message>)`, exit 4, the worktree and branch left as is —
  never `cleaned`. A session the listing places outside the project (its `cwd` not under the
  repository's main checkout, the worktree or the folder whose `.claude/worktrees` holds it) is never
  touched: `SESSION FOREIGN: <id> (<cwd>): not this project's session - nothing done`, exit 5 (CORE
  §1.17). A branch with nothing to lose needs no merged PR (#257): no commits beyond its base (origin's
  default branch; with no origin the local main or master), never pushed (no upstream configured, no
  remote branch of its name on any remote, `git ls-remote` of origin included) and the worktree clean
  (no untracked files either) — `EMPTY: <branch> has no commits beyond <base> and was never pushed -
  removed`, its session handled as for a merged one. It is removed without `--force`: `git branch -d`
  from the worktree detached at the branch's own commit (so the main checkout's HEAD being behind does
  not matter), then `git worktree remove`. After the session is stopped the worktree is checked again: a
  commit or change since the checks is `CHANGED: <worktree> moved since the checks - left as is`, exit 3;
  a failed removal puts the branch back at its commit (`REMOVE FAILED: …; branch <branch> put back at
  <sha>`, exit 1) — run it again later. One commit, a push or a dirty worktree takes the usual checks.

## Assistants
An assistant ([roles/assistant.md](roles/assistant.md), #281) is a persistent background session beside
the coordinator for work outside the project's code — logging the owner's hours from the work done,
reports, gathering information. It reads the project and the coordinator's records, keeps its own notes and
changes nothing in the project. The coordinator creates, changes, wakes and removes one only on the owner's
words, by the `coord-assistant` skill ([skills/coord-assistant/SKILL.md](skills/coord-assistant/SKILL.md)).
- **Its folder** is `coordinator/assistants/<name>/`, in the state repository: `BRIEF.md` (its job, from
  the owner's context, [the template](skills/coord-assistant/BRIEF.template.md)) and `NOTES.md` (its memory:
  what it did, the owner's corrections and standing rules). What it knows lives in these two files, so a
  long context can be compacted, or the session restarted or replaced, without loss, and its cost need not
  grow with its history. Its settings file lies outside the folder, never inside it (start-worker refuses
  a `--safety` file inside it: the guard lets the assistant write there), and outside
  `coordinator/assistants/`, so no assistant's folder can share its name:
  `coordinator/assistant-settings/<name>.json`. The assistant cannot commit: the coordinator commits its
  folder, `NOTES.md` included, together with every commit it makes in `coordinator/`, and at each sync and
  before a handoff (CORE §4).
- **Start:** `start-worker.sh --repo <root> --name "assistant: <name>" --model <model> --brief-file
  <root>/coordinator/assistants/<name>/BRIEF.md --safety <its settings> --report-to "<the coordinator>"`
  (Windows: `start-worker.ps1` with `-Repo`, `-Name`, `-Model`, `-BriefFile`, `-Safety`, `-ReportTo`).
  `<name>`: letters, digits, `.`, `_`, `-`, not dots only. No worktree and no branch: the session starts
  from the repository root, and its launch text's first line names its folder (BRIEF.md read in full,
  NOTES.md kept as its memory, both re-read after a compaction or a restart, writes only inside the folder,
  questions to `--report-to`), then the role, then the brief. Refused before anything is created (exit 1):
  a brief that is not `BRIEF.md` in that folder, a safety file whose env `COORD_ASSISTANT_DIR` does not
  name the same folder (compared as on disk — links and junctions resolved, `..` taken — `C:/...` on
  Windows, a Git Bash `/c/` form too, no trailing `/`, in one letter case where paths ignore it; a folder
  that does not exist compared as written; both start-worker scripts compare by the same bash code, so they
  disagree only by refusing), a `--safety` file inside the assistant's folder, a session of that name
  already listed (any state, `claude agents --json --all`) or a listing that fails or prints no JSON list
  (it cannot tell), and a worker's flags (`--branch`, `--base`, `--worktree-root`, `--launch-from`,
  `--contract`, `--tester-commit`, `--tester-tests`). Nothing is written into the folder by the script.
  `--assistant-dir <folder>` (`-AssistantDir`), only with an `assistant:` name (refused with any other),
  puts the folder elsewhere — it must exist, be named `<name>`, lie in a folder named `assistants`, and no
  git working tree may see it (outside every one, or ignored there): the self-test's throwaway assistant
  (`selftest assistant`) uses it; a real assistant keeps the default folder in the state repository.
- **Talk and attach:** start-worker prints `attach: claude attach "assistant: <name>"` (and `claude attach
  <id>` when the launch printed the id); the owner talks to it there, through Remote Control, or however
  its brief says. It asks the coordinator by SendMessage only what its folder, the run log and the
  journal do not hold.
- **Wake after a restart** (of the machine, after a core update or a pause): record its full `sessionId`
  at the start (the journal line). Listed and idle: a SendMessage. Listed as stopped (`done`): `claude --bg
  --resume <full sessionId> "<re-read BRIEF.md and NOTES.md, then continue>"` from the project root
  (*Pause and resume*: the same name, settings and history). Not listed, or a history so long that a
  resume would pay more than a fresh start (after a pause over an hour the cache is gone): a fresh start
  with the same brief, which reads BRIEF.md and NOTES.md — a listed old session removed first, on the
  owner's yes (start-worker refuses a second session of the name): stopped, its spend read and logged
  (CORE §7) and its status file deleted, then `claude rm <id>`, as when an assistant is removed.
- **After a compaction:** the assistant settings examples run the after-compact hook's `assistant`
  variant (`after-compact.sh assistant`, Windows `after-compact.ps1 assistant`): it tells the session to
  read in full `<COORD_ASSISTANT_DIR>/BRIEF.md`, `NOTES.md` and the core's `roles/assistant.md`, and to
  follow them, not the summary — whether or not start-worker's kept brief for the session is still there
  (it is pruned after 14 days); without `COORD_ASSISTANT_DIR` it still names BRIEF.md and NOTES.md and
  says the folder is unknown. The coordinator variant is silent in an assistant's session (env
  `COORD_ASSISTANT_DIR` set), as in a worker's.
- **A core update** changes neither its folder nor its settings (both outside `coordinator/core/`; the
  guard's path in the settings stays the same). It is paused and woken like any running session
  (UPDATE-CORE steps 4 and 6), never removed; a changed `roles/assistant.md` reaches it by a message to
  re-read `coordinator/core/roles/assistant.md`, or by a fresh start.
- **A machine move:** its folder travels with the state repository (CORE §12b); its sessions and
  transcripts do not. On the new machine its settings are filled again from the example (their paths are
  the old machine's) and it is started fresh from BRIEF.md and NOTES.md, on the owner's word.
- **Never cleaned up** (CORE §8): cleanup-worker with its session answers `ASSISTANT KEPT: <name> (<id>)`,
  exit 6, and changes nothing; `selftest verify` and `selftest clean` never count or name an `assistant:`
  session. `selftest assistant` proves the frame on the machine with a throwaway assistant on the light
  model ([procedures/SELFTEST.md](procedures/SELFTEST.md)), in the system temp, never in
  `coordinator/assistants/`; it removes that throwaway session and folder at its end — the one exception.
- **Its spend** goes to the run log as rows of role and kind `assistant`, the assistant's name in the task
  column, apart from the tasks' and the coordinator's own (CORE §7: each row's cost is its session's
  `session-tokens` cost less the earlier rows of the same name and session `start`).

## Messages between sessions
- `ListAgents` + `SendMessage` (Claude uses them itself); `notify_when_idle: true` gives one notice when
  the worker is next idle (same machine, expires after 12 h). A session **waiting on a permission
  prompt is not idle**: no notice comes; `ListAgents` shows it as `waiting` (seen on 2.1.296).
- **The session watcher in place of idle subscriptions** (#342, CORE §4 *Control*): every idle notice
  and every message starts a turn of the receiver's whole context, and a worker that reports by
  message still made 2–4 idle notices. So a session that reports by message is not subscribed; the
  coordinator (and a lead, for its workers) keeps the sessions it awaits a report from in a list file —
  `coordinator/watch.txt`, a lead's in its notes folder — and runs one watcher as a background command
  while the list is not empty: `bash coordinator/core/scripts/watch-sessions.sh --list
  coordinator/watch.txt` (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File
  coordinator\core\scripts\watch-sessions.ps1 -List coordinator\watch.txt`), with `run_in_background`.
  It polls `claude agents --json --all` every `--interval` seconds (default 120), reads the list again
  on every poll, prints nothing while every listed session is at work, and ends with one line per
  finding: `STOPPED <id> <name>`, `GONE <id or name as listed>`, `QUIET <id> <name> <minutes>`
  (exit 0); `EMPTY` when the list is missing or holds no session (exit 0 — with nothing to watch it does
  not run); `ERROR <first line>` when `claude agents` failed on two polls in a row (exit 1) — a call
  past `--agents-timeout` (default 60 s) is a failed poll: the watcher kills only the listing process
  it started itself (by its own `$!` / process handle), never a process under it or one looked up by
  name or id — a descendant of a hung listing is left running.
  **States, as measured:** the listing gives `state`, and `status` (`busy` / `idle`) only while the
  session's process lives — a live session between turns is `done` + `idle`, an exited one `done`
  with no status. State `working` or status `busy` = at work; state `stopped` / `failed` (any status),
  or `done` with no status = STOPPED; `done` + `idle` and any other state (`idle`, `blocked`,
  `waiting` — a permission prompt or a limit) = quiet: QUIET after `--quiet-minutes` (default 20),
  counted by the watcher from the first poll that saw it quiet and started again after a poll that saw
  it at work. A list line is the session's short id (`id` in the listing) or its whole name, with an
  optional limit of its own at its end, ` @<n>` minutes (a lead waiting for its workers: `<id> @120`);
  a UTF-8 BOM, blank lines and comments (`# …`, a `#` followed by a blank or the line's end) are
  skipped, `#12 worker: Fix` is a name. The only files it writes are the listing's output, in a fresh
  temp location per call (read from files, not a pipe, so a leftover child cannot hang it), deleted at
  once; it never stops, messages or changes a session; `--once` polls once (a manual check). The list is committed in `coordinator/` with the
  event's journal line; the sync starts the watcher when the list is not empty. Tests: `tests/watch-sessions/run.sh
  sh|ps <powershell>` against a stub `claude`. A subscription stays only for a session no message is
  expected from (CORE §4 *Control* says which).
- **Names change:** a restarted or renamed session may come back under another name, so a report
  address written into a brief can go stale. start-worker writes
  the address it is given (`--report-to`, the coordinator's name as `ListAgents` shows it now); the
  roles fall back to the project's Coordinator and never drop a report silently. A session the
  coordinator starts any other way (a raw `claude --bg`) has no such net: after a rename, tell every
  running session the new name (CORE §4, *Control*).
- **A SendMessage a hook refused** (the guard's hook error or timeout — on a loaded machine it can run out
  of time, and with `onFailure: "block"` the message is not sent): send it again once; refused again, the
  role uses its fallback address (the project's Coordinator, roles/worker.md step 5) and says so in its
  report — never drops a message silently. The guard's `timeout` is 30 s for this; `selftest hooks`
  fails a shorter or missing one (#290).
- **Subscribing right after a start can race:** the new session may not be listed yet ("No agent named
  … is reachable"). start-worker waits until `claude agents --json` lists it; if a subscribe still
  fails, retry once a few seconds later. One subscription per expected report — every re-subscription
  to an idle lead (idle while its workers run) only brings another notice for the same pause. (Where a
  subscription is still used: a session no message is expected from, CORE §4 *Control*.)
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
- A weekly job cannot live in a cron that expires after 7 days; the retro runs only when the owner
  asks ([procedures/RETRO.md](procedures/RETRO.md), #242).

## Safety
- **Permission rules:** `deny` → `ask` → `allow`; a deny always wins. Compound commands are split
  (`&&`, `;`, `|`) and every part must match an allow rule. PowerShell rules look like Bash rules:
  `PowerShell(Get-Content *)`. Read-only Bash commands are auto-allowed; PowerShell cmdlets are not.
  [permissions](https://code.claude.com/docs/en/permissions.md)
- **Never allow** patterns that run arbitrary code (interpreters, `npx`, `npm run *`, `gh api *`,
  script blocks).
- **The real enforcement is on the code host:** branch protection — PRs required, checks required, a
  human review required in the strict preset. Rules and hooks on the machine are a safety net, not a wall.
- **A worker's draft PR:** the worker safety file allows `gh pr create --draft *` (Bash and PowerShell),
  the one narrow allow rule it holds for a write: Claude Code's auto mode resolves a narrow allow rule
  without its classifier (permission-modes docs), which had refused some workers' draft PRs; a compound
  command still needs every part allowed. `gh pr ready` and `gh pr merge` stay denied where the preset
  denies them (#261). The `*` would also take in `--repo <any repository>`: the guard blocks `gh pr create`
  with `--repo` / `--repo=x`, a short-flag group holding `R` (`-R x`, `-Rx`, `-dR x`), the same before `pr`
  (`gh -R x pr create`), or `GH_REPO=` before gh in the same command. It cannot see a `GH_REPO` exported
  earlier or inherited from the session's environment, nor which remote gh takes the base repository
  from: keep `GH_REPO` out of the worker safety file's `env`.
- **The guard reads a command's text, not only what will run:** `git push` written inside a string or a
  here-string of the same command (a brief written to a file) is read as a push and may be blocked.
  Write such text with the Write tool. The guard does not strip strings on purpose: that would let
  `pwsh -Command "git push origin main"` through (#264).
- **Hook:** a `PreToolUse` hook (`scripts/hooks/safety-guard.sh`; Windows `safety-guard.ps1`, the same
  rules, both checked against `tests/safety-guard/cases.txt`) guards only the irreversible:
  pushing, force-pushing or deleting the protected branches (main / master and those of `COORD_PROTECTED_BRANCHES`,
  next bullet — in any refspec form:
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
  is no way around the rules. Discarding files in a repository's main checkout is blocked too (#263),
  by the cwd, a `cd` or `git -C`: `git clean` with `-f` (not with `-n` / `--dry-run`), `git reset
  --hard`, `git checkout -- <paths>` / `<ref> -- <paths>` / `.` / `-f`, `git switch -f` /
  `--discard-changes`, `git restore` of the working tree (not `--staged` alone), `git stash drop` /
  `clear`; a linked worktree, or a repository whose top folder lies under `.claude/worktrees/` or a
  declared worktree root, passes (a plain folder there belongs to the project and does not); a folder
  that cannot be known (a variable, not a repository, `--git-dir` / `--work-tree` / `GIT_DIR=` /
  `GIT_WORK_TREE=` pointing elsewhere) blocks — with or without
  `COORD_PROTECTED_ROOT`, which a subagent under the coordinator's own settings does not have. It parses
  the command like a shell: line continuations are joined, separators inside quotes (a commit
  message, a PR body) do not split, `{ … }` groups and PowerShell script blocks split like `( … )`,
  wrappers are skipped with their options (`sudo -E`, `env -i`, `timeout 30`, `nice -n 5`, `stdbuf
  -oL`, `builtin`, `noglob`, `time`, `nohup`, `exec`; also given as a path or with `.exe`, as the
  command itself: `/usr/bin/env`, `timeout.exe`, `git.exe`), `$(…)`, `bash -c` / `pwsh -Command` (or a prefix
  such as `-Com`) and a heredoc fed to a shell
  are checked as commands of their own. Work-branch operations (push, force-push, rebase, amend,
  reset, deleting work branches; `reset --hard` outside a main checkout) and tag-only pushes pass. Exit
  code 2 blocks and shows the reason. Input it cannot read (not a JSON object) blocks; a BOM before the object is dropped;
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
  non-blocking error, or no hook at all (`--expect probe`: a session told to `echo` the self-test's probe
  token; `--expect edit`: the edit probe). `selftest probes` starts the probe sessions itself and checks
  each the same way, with no owner step (SELFTEST step 2a): while it runs, the guard blocks a Bash or
  PowerShell command holding the token it writes into the project's `.claude/coordinator-probe.txt`
  (the first line, 16+ letters, digits and `-`; read from `CLAUDE_PROJECT_DIR`), so a harmless `echo`
  shows the hook loaded, run and its exit 2 honoured, with nothing for the auto mode's classifier to
  refuse (#259). So the settings example runs the
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
  Ordinary shell syntax is read as bash runs it, in both scripts (#345): a Bash command's unquoted brace
  expansion (`{main,}`, `m{a,}in`, `{x,{main,y}}`, `ma{h..j}n`) is judged as every word it makes, and the
  command after `find -exec` / `-execdir` / `-ok` / `-okdir` (up to `\;` or `{} +`) as a command of its
  own; a quoted brace, `{main}`, `{}`, `${var}` and `@{u}` stay as written. A word making more than 64
  words is not expanded, and the command is refused when the guard reads it (git, gh, rm, find, cd …)
  or the word is its command word. Still out: other expansions (a glob such as `ma?n`, `${x/…}`), and
  braces in a PowerShell command (PowerShell has no brace expansion).
  Hooks see only the tools their matcher names (the guard: the shell tools, the edit tools — next
  bullet — and SendMessage, *Own sessions only* below) — **MCP tools are covered by deny rules only**
  (the settings examples deny the GitHub MCP write tools; rename them to the server name connected on the machine and add
  any other server that can write to a protected branch). Whether hooks run in
  `bypassPermissions` *(unconfirmed)*. [hooks](https://code.claude.com/docs/en/hooks.md)
- **Which branches are protected:** `main` and `master` always, plus the names in `"env":
  {"COORD_PROTECTED_BRANCHES": "dev release/1.0"}` in the worker safety file — separated by spaces and
  / or commas (`dev, release/1.0`). A list **adds to** main and master, never replaces them (a setting
  cannot unprotect main); a name given twice, or in another letter case, counts once. Each name is
  matched whole and literally, letter case ignored: no patterns or globs (`release/1.0` is not
  `release/1x0`, `release/*` is only a branch named so). Every check of the guard above covers each
  protected branch, and the block names it (`push to a protected branch (dev)`, `deleting a protected
  branch (dev)`, `push while on dev`). Empty or unset: `main` and `master` only. The names are the
  project's *Protected branches* setting (`PROJECT.md`, asked in the init quiz, one-time step
  `protected-branches`). The static push deny rules of the settings examples name `main` and `master`
  only: a project listing more branches adds the same rules for each (`Bash(git push origin <b>)`,
  `… <b> *`, and the `--force`, `-f`, `--force-with-lease` and `PowerShell(…)` forms) — INIT writes
  them with the env entry. `selftest hooks --settings` reports the protected branches (`protected
  branches: main master (default)` when no name is set) and, when names are set, checks per protected
  branch — main and master included — that this core's guard blocks a push to it.
- **The owner's working copy and the edit tools:** a worker started from the project folder
  (`start-worker` from the repository's root, EnterWorktree) works in its own copy under
  `.claude/worktrees/`, but an `Edit` / `Write` / `MultiEdit` / `NotebookEdit` with an absolute path can
  still reach the owner's checkout. With `"env": {"COORD_PROTECTED_ROOT": "<the project root>"}` in the
  **worker** safety file (never the coordinator's own settings: the coordinator edits there — it writes
  `coordinator/` inside the root — so on its own files `selftest hooks` says `SKIP … COORD_PROTECTED_ROOT
  not set`, which is expected there and not offered by UPDATE-CORE step 3, #256) and those
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
- **The assistant mode** (#281, *Assistants*): an assistant's settings come from
  [settings.example.assistant.json](settings.example.assistant.json) (Windows:
  [settings.example.assistant.windows.json](settings.example.assistant.windows.json)) — the worker
  safety file with env `COORD_ASSISTANT_DIR`, the absolute path of the assistant's folder. With it set, the
  guard holds the session to an assistant: `Edit` / `Write` / `MultiEdit` / `NotebookEdit` only inside that
  folder (as written or as on disk; also inside `COORD_PROTECTED_ROOT`, whose worker rule then gives way),
  any other path, no path, or a path holding a line break refused; a value that is not absolute, or is `/`
  or a drive, refuses every edit (a broken mode never fails open). git only to read (log, show, diff,
  status, a branch or tag listing, a config read, fetch with no local destination …: commit, push, merge,
  checkout, stash, add and every other write refused, in any repository), and never a read that can run a
  command or write a file: git's own `-c`, `--config-env`, `--exec-path=`, `--git-dir`, `--work-tree`, any
  variable set before git (`GIT_PAGER=`, `PAGER=`, `HOME=` …), a `GIT_` variable set anywhere in the command
  (`export`, `$env:`, `Set-Item env:`), a read's `--output`, `--ext-diff`, `--upload-pack`, `--receive-pack`,
  `--exec`, `--open-files-in-pager` (also abbreviated), grep's `-O`, ls-remote's `-u` are refused, while
  `git log`, `git fetch origin`, `git grep x`, `git diff` pass; gh only to read (`pr` / `issue` /
  `repo` … `list`, `view`, `status`, `diff`, `checks`; `gh api` with no method and no fields, or `-X GET`;
  graphql without a mutation). gh is an allowlist there: only these reads pass — a group's `list`, `view`,
  `status`, `diff`, `checks`, `watch` (`pr`, `issue`, `release`, `repo`, `run`, `workflow`, `label`, `gist`,
  `cache`, `ruleset`, `project`, `secret`, `variable`, `search` …), `gh api` by the read rules above (GET or
  HEAD, graphql without a mutation), `gh auth status`, `gh --version`, `gh help`; every other gh command is
  refused (`gh alias set` and a call of an alias, `gh extension install`, `gh auth login` / `logout` /
  `refresh` / `setup-git`, `gh config set`, `gh codespace create`, `gh ssh-key add`, an unknown group …).
  The examples also run the after-compact hook's `assistant` variant (*Assistants*); the guard's
  self-test there probes the pushes with the mode off and the mode's own verdicts with it on, so it says
  `safety-guard: OK` in an assistant's session. Unset or empty,
  nothing changes. **The limit:** shell writes (a
  redirection, `sed -i`, `cp`) are not guarded, and MCP tools pass the hook — the assistant's role and
  brief hold it to its folder there, and the write tools of a connector its brief does not name go into
  its settings' deny list. Nor does the guard's reading of git and gh see `GH_BROWSER` / `BROWSER`, `gh --help <extension>`, abbreviated options of
  `git branch` / `tag` / `config`, a variable other than `GIT_…` exported earlier (`export PAGER=…`), or
  git run inside a repository made in the assistant's own folder. This file only, never the coordinator's own settings: the coordinator edits its state repository and
  more.
- **Own sessions only (CORE §1.17):** `claude stop / rm / respawn / attach <id>`, `claude --resume <id>`
  and SendMessage reach every session on the machine; the coordinator and every role act only on those
  whose `cwd` (`claude agents --json --all`) is inside the project root, its state repository or its
  worktree roots. Three layers: the rule itself; the scripts' own checks (`cleanup-worker` refuses a
  foreign session: `SESSION FOREIGN`, exit 5); and the guard as a backstop, in the sessions whose settings
  hold it (workers and leads; the coordinator only where the owner put it in its own) — a shell command running one
  of those verbs (in any form it already reads: wrappers, `bash -c`, `.exe`, a path) or a SendMessage
  call (its `to` by name, also with a `[ref]`, id or `sessionId`; SendMessage in the matcher) is looked
  up in the listing, and a session outside `CLAUDE_PROJECT_DIR`, the repository's top and main checkout
  or the `Worktree roots` of `<root>/coordinator/PROJECT.md` is blocked (`Blocked by safety-guard: claude
  rm a session of another project (<cwd>). Ask the owner.`), whole path segments compared, as written
  and as on disk; a SendMessage to a name another project's session has too is blocked even when an own
  session has it (it may reach both, #201). Only those calls run `claude agents` (measured on Windows, 2.1.300: about 0.5-0.7 s
  more per such call). **The limit:** a session the listing does not have, a listing that cannot be
  read, a name an own session shares, and an id hidden in a variable or a script pass the guard — the
  rule and the scripts' checks are the main defence.
- **Deny rules** in `settings.example.json` are the swarm and standard baseline: the protected branches only
  (shell and PowerShell forms, force and mirror pushes, and the GitHub MCP write tools; main and master
  in the examples, plus the same rules for every other branch the project lists in
  `COORD_PROTECTED_BRANCHES`).
  Add `gh pr merge*` / `gh pr ready*` and the production MCP write tools in the strict preset (humans
  merge); the cautious override also adds
  `Read(**/.env*)` and the **stack candidates** the owner picks at init (never imposed), per kind:
  production database by CLI (`supabase db push*`, `psql *`, a migration repair) and by MCP
  (`mcp__<db>__execute_sql`, `apply_migration`, branch reset / merge / delete); function deploys and
  secrets; production deploys (`vercel --prod*`, `vercel promote*`, `vercel rollback*`, `vercel env *`);
  code-host settings and workflows (`gh workflow run*`, `gh secret set*`, `gh release*`, `gh api *`).
  A deny rule matches the start of a command only: `Bash(git push*)` misses `git -C <dir> push` and
  `cd <dir> && git push` (seen, #202), so deny rules cannot say "no push at all"; the guard's own
  rules, which read every form, block pushes to the protected branches only.
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
- **In a worktree session, through the PowerShell tool.** In a session isolated in a worktree, Claude
  Code refuses `pwsh` / `powershell` started from the Bash tool ("cannot be shown not to run git"),
  even after a `cd` into its own worktree; the same `pwsh -File` through the PowerShell tool runs
  (measured, #240). A check that starts PowerShell (a `.ps1`, a project script calling one) goes
  through the PowerShell tool there. The verifier and tester roles list it in `tools:`; where there is
  no PowerShell tool (macOS, Linux) the name is ignored (measured).
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
  repositories with stub `claude` and `gh`; the real `claude` is never called), and beside it
  `tests/workers/assistant.sh sh|ps <powershell>` (an assistant's start and cleanup-worker with a listing
  that fails or prints no JSON list, refused and nothing touched; one comparison of folders in both
  start-worker scripts; `--assistant-dir`). The others take the same
  `sh|ps <powershell>`: `tests/check-contract/run.sh` (the fixture contracts against their expected
  output), `tests/check-core/run.sh` (a core copy with a wrapped feature field and a script without its
  pair), `tests/check-scripts/run.sh` (odd folder names, extensions in capitals, 5.1's rules, a `bash`
  that checks nothing), `tests/session-tokens/run.sh` (the fixture transcripts counted exactly, their time lines included),
  `tests/session-insights/run.sh` (fixture transcripts: the cases its top comment lists),
  `tests/retro/run.sh` (a run log with a history, a thin previous week, a week
  with a rework, an escalation, a failed run, a lead and a subagent row, a project's own kind and an open
  wait, a self-test and a probe left out, a kinds map, logged estimates and rebuilt forecasts, an unknown result, a sibling worktree root; its journal, escapes and transcripts; the local report and the
  public body against their expected files, the folder's name absent from the public body, a week with too
  little data and no transcripts, CRLF and a BOM; the public check failing on an injected path, the
  folder's name, free text and a foreign label; the proposal check; `--new-id`; usage errors),
`tests/run-stats/run.sh` (fixture run logs: a task's worker, tester and verifier rows summed, a real log's cost cells read by their leading number and a verifier's `done` / `pass`, a lead
and its sub-runs summed, only the last 10 tasks counted, old rows without the time columns, `-`
values, under 4 tasks, even counts, `--per-run`, no header or one in another order, a header only,
CRLF with a BOM, a missing file; `--limits` on `tests/run-stats/limits/`: trusted, guessed and previous
ratios, a block that fits and one that does not, a window that has reset, no `rate_limits`, CRLF with a
BOM, models priced apart),
  `tests/merge-queue/run.sh` (a stub `gh` answering from a state folder: merged, behind and updated, a
  conflict, a merge of main that touched the PR's files with and without shared globs, a re-run once and
  a second failure, the approved commit, a push while it waits, superseded runs cancelled, closed / draft
  / no checks / a refused merge, a dry run, `status`, usage errors and a failing gh),
  `tests/report-issue/run.sh` (a stub `gh` that logs every call: one signature from two machines' errors,
  at most 120 characters, the `.ps1` line the `.sh` line, no path tail, e-mail or host in it; FIXED UPSTREAM
  (the newest fix), closed as not planned going on,
  REPEAT with one reaction and none when it is there, `--comment-file`, CHECK with at most 5 candidates,
  FILED with its `Checked:` and `Signature:` lines, a dry run; an open match before a closed one,
  `--regression`; no write but the issue, the reaction and the comment),
  `tests/watch-sessions/run.sh` (a stub `claude` answering scripted listings: each finding, state and
  status, the quiet time from the first quiet poll and restarted after work, a line's own limit,
  comments and names, the list edited between polls, one failure retried and two in a row an ERROR, a
  hung listing past `--agents-timeout`, JSON without a final newline, a BOM, the interval kept,
  nothing written),
  `tests/selftest/hooks.sh` (every settings fixture against its expected output, the steps' usage
  errors), `tests/selftest/probes.sh` (`selftest probes` against a stub `claude` that feeds the token
  probe's `echo` to this core's guard and writes the transcript; `hookcheck --expect probe`),
  `tests/selftest/assistant.sh` (`selftest assistant` against a stub `claude`: the pass, each FAIL, the
  session and its temporary folder removed at the end),
  `tests/selftest/prepare.sh` (prepare and verify: CORE-FINDINGS.md, a base only on the remote,
  a non-ASCII folder) and `tests/selftest/core-copy.sh` (the checks on a project's cloned core copy). On
  Windows, the ones that read native output or print `§` run the `.ps1` with the console on code page 866,
  as on a Russian Windows.

## CI
- **The code host the scripts talk to is GitHub,** through `gh`: the merge queue, cleanup-worker's
  "is its PR merged" check, `run-stats --task --pr-json` and INIT's read of the protected branches. On
  another code host (GitLab, Bitbucket, Azure DevOps …) the rules are the same and the coordinator takes
  those steps by hand with the host's own tool: one approved PR at a time on its approved commit, the
  sessions whose PRs change the merged files told to merge main, the merge confirmed before any cleanup
  (CORE §4a, §8); INIT's summary names them (support for another host is built when a project needs it).
- **Local test runs:** a long run never under a short tool timeout — a killed run looks like a crash;
  start it in the background and wait for its end. What a test starts (a server, a browser, an app)
  ends with it: on Windows a job object (or the runner's own kill of the process tree), on macOS / Linux
  a process group (Linux `setsid`; macOS and bash 3.2: `set -m`, so a background job gets its own group;
  ended with `kill -- -<pgid>`) (#237).
- **The merge queue** (CORE §4a): `bash <core>/scripts/merge-queue.sh land 12@5f3e2a1 14@9c0d1e2
  --method squash --shared 'messages/*' --shared 'docs/decisions.md'` (Windows: `powershell -NoProfile
  -ExecutionPolicy Bypass -File <core>/scripts/merge-queue.ps1 land -Pr 12@5f3e2a1,14@9c0d1e2 -Method
  squash -Shared 'messages/*,docs/decisions.md'`), from the project's checkout, as a `run_in_background`
  command: it polls each PR's checks every minute (`--poll`), up to two hours (`--timeout`). The method
  and the shared globs come from `PROJECT.md` *Shared files*; `@<sha>` is the commit the verifier
  approved. `status` (the same globs) before planning; `status --touches <path>…` (`-Touches a,b`) lists
  the open PRs changing a task's `touches` (start-worker runs it). Each merge ends with an
  `AFTER MERGE` line, the event table's merge row (CORE §4); never filter it out. It calls only `gh`, never `git`: the owner's
  checkout is left as it is, pulled after the merges as before.
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
  delegation, WARN goes into the brief. `--field <key>` / `-Field <key>` (read-only): when the contract
  passes, only that key's value as the checks read it, on one line, exit 0; else the usual ERROR lines
  and exit 1 — start-worker's tests_first gate asks it, one parser (#276); with no key, or an empty one,
  the usage and exit 2 in both shells (#288). `scripts/check-core.sh|.ps1 [repo]` — the core's links and §
  references (CORE §10), and the feature map [FEATURES.md](FEATURES.md) in sync with the files. Windows: `powershell -File scripts\check-core.ps1`.
  `scripts/check-scripts.sh|.ps1 [folder ...]` — every `.sh` (`bash -n`) and `.ps1` (PowerShell's own
  parser; under `powershell` for 5.1's rules) parses; `<file>:<line>: <message>` per error, nothing
  installed. A language with no shell on the machine is listed as skipped, never as passed. Run it on
  the project's coordination scripts too (CORE §12a, UPDATE-CORE). A project script that needs
  PowerShell 7 says so on its first line, `#Requires -Version 7`: 5.1 then refuses it with a clear
  message instead of a parse error, and check-scripts parses it with `pwsh` (skipped where there is
  none). On one machine the `.sh` and the `.ps1` give the same verdict: both use Windows PowerShell 5.1
  where it exists.
  `scripts/selftest.sh|.ps1 scripts|env|hooks|hookcheck|probes|prepare|verify` (in a project: the state repository, evidence kept;
  `probes` starts the guard's probe sessions itself, up to about 5 minutes: a background command;
  `assistant` (#281) starts a throwaway assistant the same way, up to about 5 minutes, and ends with
  `assistant: <n> PASS, <m> FAIL`)
  and `sandbox|clean` (the core itself: a sandbox at a fixed path, which `clean --keep` resets to its
  first commit and keeps, so the owner trusts its repo once; a full `clean` removes it) — the scripted steps of the self-test
  ([procedures/SELFTEST.md](procedures/SELFTEST.md)); `PASS` / `FAIL` / `SKIP` lines (`probes`: `BLOCKED` too), exit 1 on a FAIL (or a `BLOCKED`). The
  `.ps1` runs the `.ps1` scripts under every PowerShell on the machine (5.1 and pwsh).

## Usage and limits
- **Model ladder** (CORE §7): `claude auth status` gives the login method (`authMethod`) and
  `subscriptionType` (e.g. `max`; seen on 2.1.296, not in the docs, so a hint); the status line gives
  the 5-hour and weekly use on Pro / Max only, with no per-model window; `/usage` shows a *Current week
  (Fable)* row when the plan includes Fable (Max and premium Team / Enterprise seats: Fable draws from the
  weekly limit, faster than other models, up to 50% of it; Pro and standard seats: usage credits only —
  [Fable on your plan](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan);
  the limits are shared across models, [errors](https://code.claude.com/docs/en/errors)). Probe a model
  in the cheap form: `claude -p --model <id> --tools "" --strict-mcp-config --system-prompt "Reply with
  the single word ok." --output-format json "ok"`. Its cost (at API list price, CORE §7a *The unit*) is
  a range, set mostly by the prompt cache: a
  cold first call writes the whole prompt to the cache, and the folder's CLAUDE.md files and the auto
  memory add to that prompt even with `--system-prompt` (measured on 2.1.296: Haiku ≈ $0.0005–0.0012,
  Sonnet ≈ $0.024, Opus ≈ $0.050, Fable ≈ $0.016–0.12; Haiku from an empty temp folder wrote 4347
  cache tokens against 2402 from a repo folder — an empty folder is not reliably cheaper). The bare
  `claude -p --model <id> "ok"` loads the full system prompt and tools — $0.47 on Fable on a real project.
  Not available: a non-zero exit or `"is_error": true`; never test `subtype`, which can say `success` on
  an error. A success does not prove the plan includes the model: in `-p` mode a Fable request is billed
  to usage credits without asking when they are on, and fails with an API error when they are off
  ([model-config](https://code.claude.com/docs/en/model-config), *Fable and usage credits*) — so Fable
  counts as available only with the owner's answer that `/usage` shows its row (CORE §7). A model's limit
  shows only as a message ("You've hit your Opus limit", a Fable limit or usage-credits message);
  switching family keeps working. List prices: the Claude pricing page, copied into BINDINGS.
- **Tokens and cost per run** (CORE §7 run log): `scripts/session-tokens.sh <session-id>` (Windows:
  `scripts/session-tokens.ps1`; the 8-character id that `claude --bg` and `claude agents` print works
  as a prefix) when the run ends. It prints one line per model and a `total` line summed from the
  transcript in `~/.claude/projects/`, subagents included — input and cache counts exact, **output a
  lower bound** (the transcript keeps the count from before a message finished) — and a `cost` line:
  the status line's `cost.total_cost_usd` for that session (cumulative, at API list price; on a
  subscription for comparing runs; needs the status line installed). **After a normal stop** (`claude
  stop <id>`, idle or mid-tool-call, or the process exiting) Claude Code appends to the session's own
  transcript a `cost-state` record with its totals — `totalCostUSD` (equal to the status file's cost to
  the last digit) and `modelUsage` per model, subagents' requests included; a resumed session restores
  and accumulates them, so a later record holds the whole total (measured on 2.1.296; the docs describe
  it — [cost-tracking](https://code.claude.com/docs/en/agent-sdk/cost-tracking): "saves the session's
  totals to its transcript when the process exits normally" — the record's name is internal). When the
  transcript's **last** such record has no assistant message after it, session-tokens takes the model
  and `total` lines from it — `out=<n>` (**exact**) instead of `out>=`, and `thinking=<n>` at the end
  of the line (shown, not added to the total) — and the `cost` line from its `totalCostUSD` (before the
  status file's). Otherwise (no record: a crash, a session still running; or one that ran after its
  stop) the lines are summed as above. The `time` line always comes from the timestamps, `--since`
  always sums the messages, and a subagent read by its `agentId` has no record of its own. A wrapper
  that parses `out>=` must accept `out=`. The status JSON's
  `context_window.total_input_tokens` / `total_output_tokens` are the **last request's** usage, not the
  session's (measured on a real project), so tokens always come from the transcript. No `cost` line → the tokens
  per model times the list prices, `cache_write` at the **1-hour** price (Claude Code writes 1-hour
  cache entries, `prompt_cache.ttl: "1h"` in the status JSON; on a real project this matched the status cost to
  the cent). **A subagent** (the Agent tool) has no session id and no status file: pass the `agentId`
  its result gives (or a unique prefix) — session-tokens reads `<parent>/subagents/agent-<id>.jsonl`
  and prints its own tokens per model, never a `cost` line; its cost is those tokens at list price. It
  is already inside its parent session's lines and cost, so its run-log row says `in <parent>` and a
  sum of the project's spend counts it once. Its output shows as `out>=`, a lower bound: a subagent is
  never stopped, so it gets no `cost-state` record, and its transcript keeps only each answer's output
  count at the answer's start (measured: `out>=158` for a 1,500-word report). Its cost is therefore a
  lower bound; the number that counts is its parent's, which holds it exactly. The task notification's
  `subagent_tokens` is the subagent's last context size, not its spend (#232). **Time per run** (CORE §7a): for one session or subagent
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
  or `--prune`. **The order** when a run ends: `claude stop <id>` (the short id, *Workers*; its process
  exits normally and writes the `cost-state` record), then read its tokens, cost and time (now from the
  record; a failed read retried once with the full command, never left as `n/a`), then delete that
  worker's `sessions/<sessionId>.json`, then `claude rm <id>` (the short id again; session-tokens still
  reads a removed session's transcript, but not a status file's cost line), and check that `claude
  agents --json --all` no longer lists it. A read that still shows `out>=` after the stop has
  no record (the process crashed or was killed): it is the summed reading as before, and the run's
  report notes it. The status line writes a file for every
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
  `$env:CLAUDE_CODE_SESSION_ID`) prints its own tokens, cost and time — a lead reads itself that way. That
  reading never holds the whole turn in progress (measured on 2.1.296, macOS and Windows): the tokens come
  from the transcript, which gets a message only after its tool calls return (zero at a session's first
  call); the cost comes from the status file, which the status line refreshes after each model response —
  so on the first turn it is zero or only the first responses (Windows: $0.0039 of a $0.0062 turn), and
  later it lags by the rest of the turn. Read it at stage boundaries; a zero or small first reading is
  "not yet".
- **Where sessions lose money, time, quality or stability** (CORE §7a, the retro's input):
  `scripts/session-insights.sh <session-id | prefix | agentId | transcript.jsonl>` or `--since <UTC time
  | Unix seconds>` (`session-insights.ps1 <id>` / `-Since`; `--detail` / `-Detail`), the same lookup
  as session-tokens: a session is its transcript and its subagents', `--since` every transcript on the
  machine, each record by its own timestamp. It only reads and prints; nothing is sent anywhere. With
  `--since`, the retro's filters: `--until <time>` (`-Until`: records before it only); `--skip-tests`
  (`-SkipTests`: no probe or self-test session — a name with `probe`, `selftest` or `self-test` as a word
  before its first colon, a task `#st<n>`, or a first cwd inside a `coordinator-selftest` folder; a
  product task whose title only mentions a self-test stays); `--project <folder>` (`-Project`: only the
  sessions whose first cwd is the folder or inside it, `\` read as `/`, case ignored, `C:/x` as `/c/x`;
  several folders joined by `|` — the root and its worktree roots) —
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
- **The retro** ([procedures/RETRO.md](procedures/RETRO.md)): `scripts/retro.sh <RUNS.tsv> [--week
  <YYYY-MM-DD>] [--project <root>] [--journal <LOG.md>] [--escapes <ESCAPES.tsv>] [--no-insights]`
  (`retro.ps1 <RUNS.tsv> -Week … -Project … -Journal … -Escapes … -NoInsights`). The week is Monday to
  Sunday UTC holding `--week` (default: the last complete week), against the 7 days before it; the
  project root defaults to the folder above the run log's, the journal and escapes to `LOG.md` and
  `ESCAPES.tsv` next to it. A task is its rows as in run-stats, in the week of its latest row date; rows of
  a task `st<n>` or `0`, or a kind or role naming probe or self-test, are left out; a task-less row is the
  coordinator's own cost; a cost cell counts by its leading number; a result by its first word (`done`
  and `pass` as `approved`). The transcripts: `session-insights --since <week> --until <its end>
  --skip-tests --project <root>|<worktree roots>|<root>/.claude/worktrees` per week, the worktree roots
  from `PROJECT.md` *Settings* *Worktree roots* next to the run log (split by `,` or `;`, relative to the
  root). It prints, tab-separated, `retro` with the weeks, `axis measure week
  previous` and a line per measure — *cost*: `tasks merged median_per_task total coordinator
  per_merged_task`; *speed*: `ready_median work_median owner_wait_median owner_wait_open` (the owner wait
  apart); *quality*: `rework_rate escalated_rate failed_rate escapes escapes_per_10_merged`;
  *predictability*: per cost and work `_forecasts _logged _rebuilt _in_range _ratio_median`, per ready
  `_forecasts _in_range _ratio_median` — a task's forecast is the estimate its run log row logged
  (`estimate` for cost, `estimate_time` for work, from its lead row, else its first worker row: a range
  `lo-hi`, in range inside it and its midpoint for the ratio; one number `n`, in range from `2n/3` to
  `3n/2`), else rebuilt: 3 or more earlier tasks of the kind and model, the last 10 before the task's first
  row, its range run-stats' 25th–75th percentile, min–max under 4; *stability*: `failed_runs guard_blocks deny_rule_blocks
  guard_around guard_false_positives guard_errors refusals tool_errors tool_calls tool_error_rate
  cache_rewrites cache_rewrites_per_task waiting_minutes rereads` — then `kind name tasks rework escalated
  failed` per kind of the week (the project's own kinds), `unknown result: <value> ×<n>` per result of the
  week no first word explains (local only), and the week's `block` / `refusal` lines. The public body
  groups the kinds by `ROUTING.md`'s `## Kinds` map next to the run log (`<own kind> -> <core kind>`;
  unmapped: `other`). Money to the cent, minutes and
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
  the values its rows have (cost in USD, a cell's leading number — `0.0648 prices` is 0.0648, `$1.20` is
  1.20 —, `active` in minutes; empty, `-`, `n/a` or `in <parent>` are no
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
  Columns are read by the header line (first field `date`), else in CORE §7's order; `estimate` and
  `estimate_time` are not read (the forecast is the medians). Exit 1 when the
  file cannot be read, 2 on a usage error.
- **A task's time to ready and owner wait** (CORE §7a): `scripts/run-stats.sh <RUNS.tsv> --task <n>
  --pr-json <file> --waits <file>` (`run-stats.ps1 <RUNS.tsv> -Task <n> -PrJson <file> -Waits <file>`)
  prints the task row for `RUNS.tsv` when the task merges, and with `--append` (`-Append`) writes it there
  as the last line, in the file's line ends (#242): `gh pr view <PR> --json
  statusCheckRollup,mergedAt,createdAt > <file>` (or `--pr-json -` from a pipe; `-PrJson:-` in
  Windows PowerShell 5.1), and the owner questions that held the task up, from the journal, one
  `<asked> <answered>` per line in UTC (`2026-10-06T08:20:00Z 2026-10-06T08:35:00Z`; `#` comments). It
  takes the task's rows (`37`, `37.1`, … — task rows aside): `start` the earliest start, `active` the
  summed work (a subagent's row aside), kind and model as above; ready is the later of the last
  approving verifier run's (result `approved…`, `done` or `pass`) start + wall and the moment the checks were all green — per check (type,
  workflow, name) its run started last counts, so a green rerun replaces a red run, and the last
  `completedAt` of those; a check not green (red, running) or verifier rows none of which approved:
  not ready, exit 1; no checks, or no `--pr-json`: the verifier alone. `wall` = ready − start − the
  owner waits inside that span (overlaps once); `wait` = merge − ready + those waits; unmerged:
  result `ready`, `wait` `<m>+` (open — append the merged row later; the last one counts). Minutes
  rounded half up from exact seconds; the row in the file's header order, missing names (`wait` in an
  older file) appended in CORE §7's order (`estimate_time` printed empty where the header has it, never
  appended). Exit 1 also when the task has no rows or no start, or a wait
  line is no pair of UTC times.
- **Limits: percent per dollar and the block's fit** (CORE §7a): `scripts/run-stats.sh --limits`
  (`run-stats.ps1 -Limits`, the options in each shell's form: `-Spend5h`, `-CapWeek`, …) does the
  limit arithmetic, never by hand. Inputs, all optional: `--status <file>` (default
  `<config>/coordinator/statusline.json`, `<config>` = `$CLAUDE_CONFIG_DIR` or `~/.claude`);
  `--spend-5h` / `--spend-week <file>` — what `session-tokens --since <since>` printed for that window
  (`-` reads stdin, for one of them; Windows PowerShell 5.1 takes it only as `-Spend5h:-`); `--prices
  <file>`, needed with a spend — the ladder's list prices from BINDINGS *Models*, one model per line,
  `<model id> <input> <output> <cache read> <cache write>` in USD per million tokens (cache write at the
  1-hour price; `$` and ` / ` allowed, `#` comments; e.g. `claude-opus-5-5 $5 / $25 / $0.50 / $10`), then,
  in any order, `top` after the top rung's model when it stands above the strong one (Fable), and
  `not-weekly` after a model with its own limit whose spend does not count toward the weekly one (none
  known today; never Fable, which shares the weekly limit — every model spends both windows, so
  `five_hour` sums them all); the project keeps it as `coordinator/prices.txt` (one-time step `prices-file`); a spend
  model takes its own id's line, else the longest id it starts with, else exit 1; `--prev-5h` /
  `--prev-week <% per $>` (the last window's ratio); `--cap-5h` / `--cap-week <%>` (the project's caps,
  §9); `--block <USD>` (the block's estimate without its top-rung runs) and `--block-top <USD>` (the
  estimate of its top-rung runs, counted at 2.5×, CORE §7). Two steps: first without a spend, for each window's
  `since`; then `session-tokens --since <since>` per window into a file, and again with the spends. It
  prints a header and a tab-separated line per window, `window used since resets cost ratio basis left
  left_cap block fit top`: used percent (one decimal); the window's start and its reset (UTC); the account's
  list-price cost since the start (to the cent; `seven_day` without `not-weekly` models); the ratio in
  percent per dollar (four decimals) and its basis — `trusted` (the window has risen ≥ 10 points: used
  over cost), `previous` (under 10, `--prev-*` given), `guess` (under 10: used over cost), `-` (none); the
  dollars left before 100% and before the cap (rounded down); the block's percent and `fits` / `does
  not fit` within the cap (100% without one); the `top` models' share of the window's cost in percent,
  one decimal (`-` without a cost or a `top` line; CORE §7's guard rail (c) reads `seven_day`'s). Fixed-point arithmetic, so the `.sh` and the `.ps1` print
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
  Windows `"statusLine": {"type": "command", "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File \"C:/ABSOLUTE/PATH/scripts/statusline.ps1\"", "refreshInterval": 10}`
  (`powershell` instead of `pwsh` where PowerShell 7 is missing); macOS / Linux
  `"statusLine": {"type": "command", "command": "bash /ABSOLUTE/PATH/scripts/statusline.sh", "refreshInterval": 10}`. It
  appears after the next response. `refreshInterval` (seconds, minimum 1) also re-runs the script on a
  timer, so a session waiting with no events (a coordinator waiting on its workers) keeps its status
  file fresh.
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
   user settings): the status line if the owner wants it (CORE §3, *Installing it* above),
   `crossSessionInbound: "accept"` and the after-compact hook with `coordinator` (*Workers*).
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

# Initialization procedure

Part of the coordinator core, moved out of `CORE.md` (§2 details and §3) so it is read only when needed.
Same authority as `CORE.md`; the hard rules of CORE §1 apply.

## Details of the start sequence (CORE §2)


- **Existing project with its own rules** (other agents' formats — `.cursor/rules`, `AGENTS.md`, rule
   files, memory notes, a previous coordinator): the coordinator **defines the project rules** in its
   layers, for **Claude only**:
   - collect every existing rule, rate its importance, find duplicates, contradictions and stale ones,
     and contradictions between docs;
   - propose the merged `PROJECT.md` / `BINDINGS.md` to the owner, item by item where it matters;
   - after the owner's yes, the Claude layers are the single source; retiring the old formats is a
     refactor task the owner approves.
- **Platform:** detect the operating system (Windows, macOS, Linux) and the shells available
  (PowerShell, bash, zsh) on this machine; record them in `BINDINGS.md`. Use that platform's commands,
  paths and tools; never assume another OS. Where a project runs on several machines or OSes, bindings
  give each command per OS, and scripts meant for everyone are written to run on all of them (or say
  which they need). The core itself stays OS-neutral. Detect too whether the project has git, a code
  host and a tracker; anything missing → say so in one line and use the mode in
  [SOURCES.md](SOURCES.md) §3. Then install the core's roles into
  `~/.claude/agents/` (TOOLKIT *Workers*, Roles) — automatic, no question.
- **Safety check:**
  - **Branch protection on the code host** — each protected branch (`PROJECT.md` *Protected
    branches*, question 14; not only the default branch) requires a PR, passing checks and (in the
    strict preset) a human review. This is the real enforcement; missing → ask the owner to enable it
    (or record why it cannot be, e.g. the plan does not offer it). A **self-hosted runner** on a public
    repository: fork PRs never reach it and every external contributor needs approval, or the
    repository stays private (TOOLKIT *CI*). A change of the repository's visibility re-runs this check.
  - **Worker safety settings** (`settings.example.json`, Windows `settings.example.windows.json` → a
    file with absolute paths, written with forward slashes even on Windows — hooks run through Git Bash,
    which drops backslashes — passed to every worker by `start-worker --safety` / `-Safety`): the deny rules for the protected branches — the
    examples' main / master rules, repeated for every other branch of *Protected branches*, and that
    list in its `env` `COORD_PROTECTED_BRANCHES` (names separated by spaces; TOOLKIT *Safety*) — (plus, where
    `PROJECT.md` says humans merge or mark ready, `gh pr merge` / `gh pr ready`) and the safety hook,
    whose self-test must pass before any worker starts. Its `env` `COORD_PROTECTED_ROOT` is filled
    with the project root (the owner's working copy, absolute, forward slashes): with the edit tools
    in the hook's matcher, the guard then refuses a worker's `Edit` / `Write` / `MultiEdit` /
    `NotebookEdit` there outside `.claude/worktrees/` (TOOLKIT *Safety*) — in this file only, never in
    the coordinator's own settings. `selftest hooks --settings <file>` passes on it
    and on every settings file of the coordinator's own session that holds the guard (no `"shell":
    "powershell"` without `; exit $LASTEXITCODE`, forward slashes, no `$env:`; TOOLKIT *Safety*); the
    self-test proves both through Claude Code (SELFTEST step 2a). **Stack-specific denies are candidates, not impositions**: offer
    them in the quiz (TOOLKIT *Safety*, the stack candidates) and keep what the owner chooses —
    the coordinator exists to automate, and some "dangerous" actions are exactly what a project needs.
  - **No stalled workers:** workers run in auto mode and do not wait on permission prompts; with the
    cautious override (`acceptEdits`) the owner sets allow rules for routine commands (build,
    lint, test, push to the worker's own branch) at init. If a worker still waits on a prompt, the
    coordinator tells the owner — it never approves a prompt on the owner's behalf.
  - **The worker safety file in this repository is the swarm and standard baseline** (protected
    branches and irreversible removals only); the strict preset adds denies to it (merging, marking
    ready, production write tools), the cautious override more (reading env files, the chosen stack
    candidates). Claude Code's auto mode may refuse to let a session weaken
    permission files by itself — then the owner adds an allow rule for the coordinator's folder
    (`/permissions`) or makes the edit.
  - **Every MCP connector:** list its tools so the owner knows what can write where — in the strict
    preset confirm the production write tools are denied, in swarm and standard they stay available
    (§1.4); every MCP the work depends on has a CLI fallback.
  - **Production backup** (swarm and standard): the backup command and destination are written in
    `BINDINGS.md` before the first production write that git cannot undo; no recorded way to back up →
    ask the owner once, record it, then proceed.

## 3. Setup interview — the init quiz

A **quiz**, run every time the coordinator is initialized in a session. Few questions, many findings:
what only the owner can decide is **asked**; what the project already shows is **found and confirmed**
in one table; the rest is **by default** (the strictness preset, CORE §3, and `PROJECT.template.md`),
not asked, but shown in the summary. The quiz is complete (CORE §1.12) when every question below that
applies has an answer and the owner said yes to the summary.

**How to ask.** Research first: study the project read-only (code, docs, git history, CI, existing
rules and coordinators, connected tools) so every question comes with an informed recommendation. Ask
with the multiple-choice question tool (in Claude Code: AskUserQuestion), 2–4 questions per round, in
the owner's language: each has 2–4 concrete options, the **recommended option first, marked
"(Recommended)"**, with a one-line reason from the research; the owner can always answer in their own
words. Keep a list of open questions; an unclear answer goes back on it.

### 3.1 Asked — only the owner can decide

1. **Strictness — swarm, standard or strict?** Show the presets table (CORE §3) and recommend from the
   research: *swarm* for an own project in a rush; *standard* when the owner wants to approve each block
   and the risky merges; *strict* for client work reviewed by people. In every preset a worker works on
   its own inside its task and returns a finished PR. Then: which rows, if any, this project overrides.
   With it, the **spend level** (CORE §7): *balanced* (recommended) · *lean* when limits are tight or the
   plan is small · *thorough* when mistakes cost more than tokens. It leans model and effort choices and
   sets when the top rung (Fable) is used — lean: only to escalate after a failed review; balanced: also
   the hardest tasks and research; thorough: also verifying risky work — never removes a check.
2. **What we build:** the product, for whom, the current milestone and what "done" means for it —
   proposed from the README, the board, a plan document.
3. **Who is who:** solo or team; who owns the scope; who accepts work, how and where (the owner, QA, a
   business analyst, the client; preview, a device).
4. **Sources** ([SOURCES.md](SOURCES.md)): the sources-of-truth table with what was found filled in —
   confirm or fix rows; then "send everything useful you have" for the catalog. **No source of tasks
   found anywhere** (no tracker, no board, no task list in a document — a fresh project, an idea)
   → an optional question, *where will the tasks live?* — *a GitHub Project* (recommended where the
   code is on GitHub: a board with the statuses Backlog / Todo / In Progress / Testing / Done, linked
   to the repository, the team and the owner see it in the browser; needs `gh auth refresh -s project`
   once; in a client's or a team's organization only on the owner's yes) · *`coordinator/TASKS.md`*
   (private, nothing to set up, only the coordinator sees it; SOURCES §3) · *later*. A task source the
   project already has (a document, Jira, a board) stays the source: nothing is proposed then.
5. **State repository — where does it live?** `coordinator/` is always a local git (3.4); the question
   is its remote, **always private**: *the owner's account* (recommended solo) —
   `gh repo create <owner>/<project>-coordinator-state --private --source coordinator --remote origin`, first push `git -C coordinator push -u origin state`; *the team's organization*
   (recommended for a team); *local only* — warn: a lost disk or a move without a handoff loses the
   journal, the rules and the decisions. With a remote: verify `PRIVATE` (`gh repo view --json
   visibility`), push as CORE §12b says (at every event that matters, at most every 15 minutes), record the link in `BINDINGS.md`, offer a pointer the next
   machine can find (HANDOFF, *Finding it*).
6. **Risky areas:** money, roles and permissions, personal data, audit — what was found in the code
   filled in; confirm (CORE §5).
7. **Production** — only if the project has one: real users or money; the backup before an
   irreversible change (command, destination); release flags for what acts on real users.
8. **Budget:** usage caps (default: weekly 90%, short window 95%, over only with permission). The
   ladder is detected (CORE §7) and shown in 3.2, with two questions a probe cannot answer (one-time
   step `fable-on-plan`): "does `/usage` show a *Current week (Fable)* row? are usage credits on?" —
   explain: on Max and premium Team / Enterprise seats Fable shares the weekly limit, burns it faster and
   may use up to half of it; on Pro and standard seats it runs on paid usage credits only, and a probe
   succeeds there too when credits are on. No row → Fable stays off the ladder; credits on → the
   coordinator says that the guard rail on Fable's weekly share is then the only stop (CORE §7).
9. **Status line** — only when this Claude Code has none (no `statusLine` in the user or project
   settings): show `Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%`. *Yes* (recommended — the
   coordinator reads its limits from it, §9): install the script from the core copy (TOOLKIT.md).
   *No:* nothing installed; the coordinator asks about limits when it matters.
10. **The coordinator's name.** Explain in the question: workers, leads and other sessions find this
    coordinator by its session name — they send their reports to it, and when that name is not found
    they look for a session whose name contains `Coordinator` in this project's folder; with several
    projects on one machine, each has its coordinator, so the name must say which project. Options:
    *`<Project> Coordinator`* (recommended — the project's short name, e.g. `Shop Coordinator`) · the
    owner's own name, which **must contain the English word `Coordinator`** (the fallback looks for
    it; a translated word breaks it). Recorded in `PROJECT.md` *Settings*; then the owner renames this
    session — `/rename <name>` (a session cannot rename itself) — and starts it with `claude --name
    "<name>"` from then on.
11. **Core reports — send the core's bugs to its maintainer?** Explain, in the question itself:
    - **why it matters:** the maintainer can fix only the bugs that reach them. A bug of the core that
      nobody reports stays — in this project and in every other one; a reported one comes back fixed
      with the next "update the core", and this project then proves the fix itself.
    - **what happens:** when the coordinator core itself fails here (a rule, a script, a safeguard), the
      coordinator records it in `coordinator/CORE-FINDINGS.md` and, the moment it is recorded, opens an
      issue in the public repository claude-coordinator with the owner's gh account — unless the same
      issue is already open (then a "+1") or upstream already fixed it (then "update the core").
    - **what it holds:** only the core's own facts — versions, the core file, the error. Nothing of the
      project: no names, paths, code or customers ([CORE-FINDINGS.md](CORE-FINDINGS.md)). The issue is
      public and under the owner's account.
    - **saying no is fine:** nothing is sent; the findings stay in the file and can be passed on by hand.
    Options: *automatically* (recommended) · *show me each one first* (recommended for client work) ·
    *no — keep them here, I pass them on by hand*. Recorded in `PROJECT.md` *Settings*; changed later
    with "settings".
12. **Work mode — how do you give work?** Explain: the coordinator has no cycle of its own; cleanup,
    syncing the state and core reports run on events in every mode (CORE §4). Options: *by task*
    (recommended for solo work) — you name a task, it is done and reported, you name the next · *batch*
    (recommended for a team with a board or a tracker) — a command of yours (by default "start a new
    cycle") runs the batch recipe over the runnable work; the recipe is agreed in the summary. In both,
    a single task can be handed over any time. The autopilot (swarm) runs the batch recipe on its tick.
    Recorded in `PROJECT.md` *Settings*.
13. **Help improve the coordinator?** Asked softly, in the owner's language, close to: "Would you like to
    help improve the coordinator? Once a week it would send its repository a short anonymous summary —
    numbers only: what tasks cost and how long they took, how many were reworked, where the safety guard
    got in the way. No code, no file names, nothing of what the tasks were about. You can see each
    summary before it is sent, or turn it off at any time." (Russian: "Хотите помочь улучшать координатор?
    Раз в неделю он будет отправлять в его репозиторий короткую обезличенную сводку — только цифры:
    сколько стоили и длились задачи, сколько было доработок, где мешала защита. Ни кода, ни имён файлов,
    ни содержания задач. Каждую сводку можно посмотреть до отправки или выключить в любой момент.")
    Options: *show me each summary first* (recommended — and for the first week whatever the answer;
    then the owner picks the mode, [RETRO.md](RETRO.md)) · *send it* · *only me — the weekly retro runs,
    nothing leaves this machine*. Recorded in `PROJECT.md` *Settings* with the anonymous id
    (`scripts/retro --new-id`, random, never derived from a name); the weekly retro runs in every mode.
14. **Protected branches — which branches does no worker ever push to, force-push or delete?** The
    recommended answer is prefilled from the research: the repository's default branch, the branches
    protected on the code host (where a gh login exists: `gh api repos/{owner}/{repo}/branches --jq
    '.[] | select(.protected) | .name'`) and `main` / `master` where they exist. Exact names, no
    patterns (`release/1.0`, not `release/*`); the list replaces the default `main master`, so those
    two stay in it where they exist; the state repository's `state` is never one of them (CORE §12b).
    Options: *the found list* (recommended) · *`main master` only* · the owner's own list. Recorded in
    `PROJECT.md` *Settings* (*Protected branches*) and written to the worker safety file (*Safety
    check*): `env` `COORD_PROTECTED_BRANCHES` and the push deny rules for each listed branch.

Asked only when they apply:
- **Strict preset:** the production actions allowed by name; time estimates and tracking; what the
  client owes (accesses, accounts, approvals — `docs/dependencies.md`).
- **A project tied to a device** (a headset, hardware): what must not run while the owner tests.
- **Language** of the conversation and of artifacts — only if the owner's messages leave it unclear.
- **Worker permission mode** — only if the owner asks for prompts: `acceptEdits` (cautious) instead of
  `auto`.

### 3.2 Found and confirmed — one table

Stack; build / run / test / lint commands; environments and deploy; CI layout; MCP servers and their
CLI fallbacks, with each one's write tools (CORE §1.4); tracker, statuses, labels, hierarchy; branch
and commit format (from history; none → the template's); coding standards (linter configs, docs);
per-worker isolation (working copies, ports, databases, containers; the worktree roots outside
`.claude/worktrees`, one-time step `worktree-roots`); the project's own task kinds mapped to the core's
(`ROUTING.md` `## Kinds`, one-time step `kinds-map`, proposed from the run log); shared resources; serial
identifiers (migration versions); the machine's platform; the model ladder (CORE §7: one cheap probe per model, Fable counted only with the owner's answers of question 8; list prices — written also as `coordinator/prices.txt`, the prices file of `scripts/run-stats --limits`, with `top` after Fable when it is the top rung, one-time step `prices-file`; a price not on the pricing page is asked); first cost and time estimates per model from the project's existing transcripts (one pass of `scripts/session-tokens` over them: the cost and the `time` line's `active` per session, CORE §7a); technologies without a connected MCP server
(code host, tracker, design, database, hosting, docs, browser) — propose the matching servers, the owner
decides what is connected and with which rights; whether git, a code host and a tracker exist
(missing → [SOURCES.md](SOURCES.md) §3). Existing rules in other formats are merged as *Details of the
start sequence* says, and every place they differ from the core is one line in the summary.

### 3.3 By default — not asked, shown in the summary

Everything else in `PROJECT.template.md`: what follows from the strictness preset (parallel workers,
who merges, review, the approval gate, obvious review comments, autopilot and the tick, code to other
services, reports) and the template's defaults (session names, the batch recipe, commit and PR format,
progress comments, research, the radar list and the expectations checklist (CORE §4b), risk-area
rules, status page, issue fields). The owner changes any of them
with one line at the summary or later.

### 3.4 Set up without asking

- **The core** is always a local copy: clone claude-coordinator to a scratch folder, copy all its files except
  `.git/`, `.github/` and `CLAUDE.md` (`tests/` included: the self-test reads it; the core's `CLAUDE.md`
  says "you are the coordinator", and Claude Code loads a nested `CLAUDE.md` into any session that reads
  files there — every worker reading its role) into
  `coordinator/core/`, record the commit in `PROJECT.md`. Scripts, the hook, the status line and the
  roles run from there. It may be **edited for this project**; upstream changes come in only on "update
  the core" ([UPDATE-CORE.md](UPDATE-CORE.md)). A local edit useful for every project is proposed back
  to claude-coordinator (§10), with the owner's yes.
- **`coordinator/`** is the coordinator's own local git repository (the **state repository**, §12b),
  ignored by the project's git through `.git/info/exclude`, so the project's history, PRs and the client
  see none of it. Create it if missing — `git -C coordinator init`, then `git -C coordinator symbolic-ref HEAD
  refs/heads/state` before the first commit (its branch is always `state`, §12b), add `coordinator/` to the project's
  info/exclude (`git rev-parse --git-path info/exclude`: a linked worktree's `.git` is a file), first commit (layout: [state-repo/README.template.md](../state-repo/README.template.md));
  commit at every change and push per CORE §12b where it has a remote. The owner may choose to commit the
  files into the project instead — recorded in `PROJECT.md`.
- **`coordinator/CORE-FINDINGS.md`** from [CORE-FINDINGS.template.md](../CORE-FINDINGS.template.md): the
  record of the core's own failures in this project ([CORE-FINDINGS.md](CORE-FINDINGS.md)).
- **The workers' copies** live in `.claude/worktrees/` inside the project; that folder goes into the same
  `.git/info/exclude` (`/.claude/worktrees/`) unless the project's git already ignores it — start-worker
  checks and adds it before every start, so an older project gets it at its next worker; likewise
  `/.lead/`, where a lead keeps its notes inside its worktree (roles/lead.md). Never
  `.gitignore`: that is a project file its team and the client would see. Nothing else of the
  coordinator is written into the project's tree (the roles go to `~/.claude/agents/`, the hook is
  referenced by its absolute path in `coordinator/core/`).
- **The voice** is not asked: artifacts are always in the owner's voice, with no AI co-author lines
  (§11).

### 3.5 The summary

Write `PROJECT.md` (its *Settings* block first, Source per row) / `BINDINGS.md` from the answers, the
findings and the defaults; show one summary
grouped by section — asked, found, by default, and the differences with existing rules — and ask "yes,
or fix these rows". On the yes, write `coordinator/CHECKLIST.md` ([ONE-TIME.md](../ONE-TIME.md)): a line for
every catalog row — the settings as answered, the checks as run in the setup (`done`, `failed`, `n/a`)
or offered and `declined`. Then the dry run (CORE §12a) and the self-test ([SELFTEST.md](SELFTEST.md)).

### 3.6 Scenarios

- **An empty folder or just an idea.** Say in one line what is missing (no git, no code, no tracker).
  Ask questions 1–3 (the idea may be one line, "an online shop") and "send everything useful you have"
  (a brief, designs, links, a product to copy or replace). Then, **with the owner's yes, research**: one
  or more researcher subagents or sessions (§4b) on how it can be built — candidate stacks,
  architecture, hosting, services, costs and limits — returned as **an options table with a
  recommendation** and the first radar list of competitors and references (CORE §4b); the owner decides,
  and each decision goes into the decision log with its reason.
  Then **propose the infrastructure, one yes each**: `git init` (then the exclude line of 3.4 for
  `coordinator/` — before it there was no project git to hide it from); a private repository on the code host;
  a board for the tasks (a GitHub Project, or `TASKS.md`: question 4); a CI skeleton with the definition-of-done checks; branch
  protection; the state repository (question 5). Risky areas and production (6, 7) wait until there is
  code that has them. The first tasks are the project skeleton, CI and the board's
  first epics — after the dry run, on the owner's word.
- **An existing project without a coordinator.** Read everything first (code, history, CI, PRs, the
  board, README / CLAUDE.md / docs, the project's own workflow and decision documents, connected MCP,
  the platform, any device). One table of findings (3.2) with the project's own conventions kept as its
  rules (e.g. its branch and commit format); then the asked questions with what was found filled in;
  the summary lists where the project's rules and the core differ, one line each.
- **A project with an older coordinator** (rules in the repository, a remote core, no `coordinator/`):
  no full quiz — the migration plan ([MIGRATE-LAYOUT.md](MIGRATE-LAYOUT.md)) for one yes, the old
  answers mapped to a strictness preset (CORE §3), then only what the old rules did not cover (the state
  repository, the sources of truth), and every row of [ONE-TIME.md](../ONE-TIME.md) with no line in
  `coordinator/CHECKLIST.md` (built as UPDATE-CORE step 3 says) — settings as a quiz, checks offered.
- **A new machine or a teammate** (a state repository exists): find it (HANDOFF, *Finding it*); no
  access → name the repository and whom to ask, stop. With access: clone it, re-detect the "re-detect"
  rows, and instead of the quiz one "still so?" per section; then the dry run.
- **A coordinator restarted on the same machine** — the session was closed or removed, `coordinator/`
  with its journal is here, and no live session carries the coordinator name from `PROJECT.md`: work
  went on before, and may still go on. In this order:
  1. **The name first.** Ask the owner to `/rename <the coordinator name>` before anything else: the
     running workers' briefs hold that name, so their reports reach this session again.
  2. **The local core's rules.** Re-read `coordinator/core/CORE.md` (and the procedures from there)
     and follow them, not the upstream text the link pointed to: the project is pinned to its copy;
     a newer upstream is only the one line of CORE §2 step 3.
  3. **Take over the running sessions** of this project (`claude agents --json`, its folder and its
     `.claude/worktrees/`): subscribe to each (`notify_when_idle`, CORE §4 *Control*) — the old
     session's subscriptions died with it — and match each to its task in the journal and the board.
  4. Then the open questions and one "still so?" per section instead of the quiz; no dry run or
     self-test when the machine and the core commit are the same (CHECKLIST says so).
  5. **Autopilot on** (`PROJECT.md`) → recreate the tick (CORE §9, TOOLKIT *The periodic tick*).

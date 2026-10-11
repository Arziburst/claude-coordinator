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
  which they need). The core itself stays OS-neutral.
- **Safety check:**
  - **Branch protection on the code host** — the main branch requires a PR, passing checks and (for
    commercial work) a human review. This is the real enforcement; missing → ask the owner to enable it
    (or record why it cannot be, e.g. the plan does not offer it).
  - **Worker safety settings** (`settings.example.json` → a file with absolute paths, passed to every
    worker by `start-worker.sh --safety`): the deny rules for the protected branches (plus, where
    `PROJECT.md` says humans merge or mark ready, `gh pr merge` / `gh pr ready`) and the safety hook,
    whose self-test must pass before any worker starts. **Stack-specific denies are candidates, not impositions**: offer
    them in the quiz (e.g. `examples/nextjs-supabase/settings.json`) and keep what the owner chooses —
    the coordinator exists to automate, and some "dangerous" actions are exactly what a project needs.
  - **No stalled workers:** at the autonomous level workers run in auto mode and do not wait on
    permission prompts; at the cautious level the owner sets allow rules for routine commands (build,
    lint, test, push to the worker's own branch) at init. If a worker still waits on a prompt, the
    coordinator tells the owner — it never approves a prompt on the owner's behalf.
  - **The worker safety file in this repository is the autonomous baseline** (protected branches and
    irreversible removals only); the cautious level adds denies to it (merging, marking ready, reading
    env files, the chosen stack candidates). Claude Code's auto mode may refuse to let a session weaken
    permission files by itself — then the owner adds an allow rule for the coordinator's folder
    (`/permissions`) or makes the edit.
  - **Every MCP connector:** list its tools so the owner knows what can write where — at the cautious
    level confirm the production write tools are denied, at the autonomous level they stay available
    (§1.4); every MCP the work depends on has a CLI fallback.
  - **Production backup** (autonomous level): the backup command and destination are written in
    `BINDINGS.md` before the first production write that git cannot undo; no recorded way to back up →
    ask the owner once, record it, then proceed.

## 3. Setup interview — the init quiz

The interview is a **quiz**, run every time the coordinator is initialized in a session — full for a new
or adopted project (also over an existing coordinator or rules), a short per-area confirmation for a
filled one (§2 step 6):
1. **Research first:** study the project read-only (code, docs, git history, CI, existing rules and
   coordinators, connected tools) so every question comes with an informed recommendation.
2. **Ask with the multiple-choice question tool** (in Claude Code: AskUserQuestion), a few questions per
   round: each question has 2–4 concrete options, the **recommended option first, marked
   "(Recommended)"**, with a one-line reason drawn from the research; the owner can always answer in
   their own words.
3. **The first questions set the pace:**
   - **Autonomy level — autonomous (recommended, the default) or cautious?** *Autonomous:* workers run
     without permission prompts (auto mode), do routine risky work themselves — merge main, resolve
     conflicts, rebase, force-push their own branch, write to local databases and to production when
     the task needs it, with a backup before anything irreversible — and report everything; hard stops
     only for the protected branches, irreversible removals and secrets leaving the machine (§1.9,
     §1.13). Control comes from reports, reviews and rollback, not from blocks. *Cautious:* workers in
     `acceptEdits`, production read-only, the candidate deny rules applied.
   - **Commercial (client or paid work) or non-commercial (own, hobby, open source)?**
   - **Swarm or sequential?** *Swarm development* = many parallel worker sessions at once (e.g. 10+),
     the coordinator integrating as they finish. *Sequential* = logical steps one (or a few) at a time,
     each checked before the next starts. Recommend **sequential for commercial** work (the owner stays
     in the loop, fewer conflicts, every step reviewed) and **swarm for non-commercial** work in a rush.
   The answers set the defaults after them:
   - *commercial / sequential* — humans merge, "announce and wait" cycle, no autopilot and no
     unattended tick, strict review and risk tiers, time estimates (workers' freedom per the autonomy
     level);
   - *non-commercial / swarm* — the coordinator may merge on green checks and a review pass, "auto"
     cycle, autopilot if the owner turns it on, as many parallel workers as the limits and conflict
     foresight (§4a) allow.
   - **Where the core comes from — remote or local?** *Remote:* `CORE.md`, `TOOLKIT.md` and the scripts
     are always read from the public claude-coordinator repository — shared improvements arrive by
     themselves, but the core cannot be adapted to this project. *Local copy* (recommended for client
     work): the core is copied into the project's coordinator folder (in the repository or in the
     state repository, §12b) at a recorded claude-coordinator commit; it may be **edited for this
     project**; upstream changes come in **only on the owner's command** ("update the core"): the
     coordinator shows what changed upstream and what conflicts with local edits, merges after the
     owner's yes, and records the new commit. A local edit useful for every project is proposed back to
     claude-coordinator (§10), with the owner's yes.
   Also early: **where the coordinator's files live** (committed in the repository, or outside it — on
   client work the client can read anything committed). Outside the repository the folder is a clone of
   the project's private **state repository** (§12b), so the rules and the journal are never only on one
   disk — and **whose voice**
   artifacts use, including whether commits carry an AI co-author line — each a recorded answer.
   - **Status line — asked only when this Claude Code has none yet** (no `statusLine` in the user or
     project settings; an existing one is left as it is): *want a status line?* — show the example
     `Opus 5.5 (high) · ctx 837k/1M (84%) · 5h 14% · week 92%` (model (effort) · context used in this
     chat · 5-hour limit · weekly limit). *Yes* (recommended — the coordinator also reads its limits
     from it, §9): install the coordinator's status line script into the user settings (TOOLKIT.md).
     *No:* nothing is installed; the coordinator then has no usage data and asks the owner about
     limits when it matters.
4. **Complete it:** keep a list of open questions; the quiz ends only when each has an answer (§1.12).
   Then write `PROJECT.md` / `BINDINGS.md` from the answers, show a summary, get a yes.

**An empty project** (no code, maybe just a folder or an idea) starts with: is there anything to rely on —
documents, a brief, designs, an existing product to copy or replace? What is the idea, even one line
("an online shop")? Should a tracker / board be created, and which accesses does the coordinator need
for that? With the idea, the coordinator proposes — **with the owner's permission** — research by
researcher sessions (§4b) into how it can be built: candidate stacks, architecture, hosting, costs, with
an advice table; the owner picks, and that becomes the project's technology. If ideas, a stack or a
product already exist, the coordinator adapts to them instead of proposing from scratch.

Ask in the owner's language, a few questions at a time. **For every question offer a ready default** —
the defaults of `PROJECT.template.md` and the examples in `examples/` — so the owner can answer "yes,
like that". Look at the repository first and propose what it already implies.

The quiz topics (a–l):

a. **Goal:** commercial or not (asked first, above); the product, its users, the current milestone or
   sprint and what "done" means for it; solo or team.
b. **Technology:** stack, build / run / test, environments (local, preview, staging, production), CI,
   deployment, where the owner or QA tests.
c. **Tracking:** tracker, board, statuses, labels, sprint; what becomes an issue; what happens to the
   owner's wishes; estimates.
d. **The change flow** — walk it end to end and agree each step: task picked → branch → commits (format,
   how often) → push → draft PR → AI review → fixes → re-review → ready → human review (developer,
   business analyst) → fixes → merge (by whom) → deploy → cleanup. Offer the defaults; it will change as
   the project goes, so revise it whenever the owner says so.
e. **Who integrates:** client / team projects — usually humans merge, so the owner stays in the process;
   own projects in a rush — the coordinator may merge on green checks and a review pass.
f. **Identity in artifacts:** whose voice commits, PR comments and issue comments use (client work: the
   owner's, first person, no mention of AI; own project: no matter).
g. **Acceptance:** how the owner, QA or the client accepts work; re-acceptance after a requested change.
h. **Parallel work and resources:** may workers run in parallel; per-worker isolation of databases,
   ports, containers; shared resources to guard; serial identifiers (migration versions, decision
   numbers) and how they are allotted (§8).
i. **Budget:** usage caps, when to exceed them, which models are available (§7); time estimates and
   tracking for client work.
j. **Language** of the conversation and of artifacts.
k. **MCP and integrations:** detect the technologies (code host, tracker, design, database, hosting,
    docs, browser) and propose matching MCP servers; the owner decides what is connected and with which
    rights (production per the autonomy level, §1.4).
l. **Workers:** how they run (background sessions, subagents, worktrees), machine constraints (one GPU,
    one device, slow environment start-up).

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
  which they need). The core itself stays OS-neutral. Then install the core's roles into
  `~/.claude/agents/` (TOOLKIT *Workers*, Roles) — automatic, no question.
- **Safety check:**
  - **Branch protection on the code host** — the main branch requires a PR, passing checks and (in the
    strict preset) a human review. This is the real enforcement; missing → ask the owner to enable it
    (or record why it cannot be, e.g. the plan does not offer it).
  - **Worker safety settings** (`settings.example.json`, Windows `settings.example.windows.json` → a
    file with absolute paths, passed to every worker by `start-worker --safety` / `-Safety`): the deny rules for the protected branches (plus, where
    `PROJECT.md` says humans merge or mark ready, `gh pr merge` / `gh pr ready`) and the safety hook,
    whose self-test must pass before any worker starts. **Stack-specific denies are candidates, not impositions**: offer
    them in the quiz (e.g. `examples/nextjs-supabase/settings.json`) and keep what the owner chooses —
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
   - **Strictness — swarm, standard or strict?** (CORE §3, the presets table). Show the table, recommend
     from the research: *swarm* for an own project in a rush (the coordinator runs the queue, many
     workers, merges on green checks and a confirmed verdict, autopilot on); *standard* when the owner
     wants to approve each block and the risky merges; *strict* for client work reviewed by people (one
     task at a time, humans merge, every step reported). In every preset a worker works on its own
     inside its task and returns a finished PR. Then ask which rows, if any, this project overrides
     (e.g. strict, but production writes as in standard) and record them.
   - **Worker permission mode:** `auto` (recommended, every preset; no prompts, the classifier and the
     hook as the net) or `acceptEdits` (cautious: prompts, production read-only, the candidate denies).
   **The core is not asked — it is always a local copy:** clone claude-coordinator to a scratch folder,
   copy its files into `coordinator/core/` and record the commit in `PROJECT.md`. Scripts, the hook,
   the status line and the roles are used from there. It may be **edited for this project**; upstream
   changes come in **only on the owner's command** ("update the core", [UPDATE-CORE.md](UPDATE-CORE.md)):
   the coordinator shows what changed upstream and what conflicts with local edits, merges after the
   owner's yes, and records the new commit. A local edit useful for every project is proposed back to
   claude-coordinator (§10), with the owner's yes.
   **Where the coordinator's files live is not asked — it is set up automatically:** the
   project's `coordinator/` folder is the coordinator's own local git repository (the **state
   repository**, §12b) and is ignored by the project's git through `.git/info/exclude`, so the project's
   history, PRs and the client see none of it and the project's files are not changed. Create it at init
   if missing — `git -C coordinator init`, then add the line `coordinator/` to the project's
   `.git/info/exclude` and make the first commit (layout:
   [state-repo/README.template.md](../state-repo/README.template.md)); the
   coordinator commits it locally at the end of every cycle (history and undo); it reaches a remote only
   on a handoff (§12b). The core lives in it as `core/`. The owner may choose otherwise (commit the
   files into the project, or push every cycle) — recorded in `PROJECT.md`. The voice is not
   asked: artifacts are always in the owner's voice, with no AI co-author lines (§11).
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

a. **Goal:** the strictness (asked first, above); the product, its users, the current milestone or
   sprint and what "done" means for it; solo or team.
b. **Technology:** stack, build / run / test, environments (local, preview, staging, production), CI,
   deployment, where the owner or QA tests.
c. **Tracking:** tracker, board, statuses, labels, sprint; what becomes an issue; what happens to the
   owner's wishes; estimates.
d. **The change flow** — walk it end to end and agree each step: task picked → branch → commits (format,
   how often) → push → draft PR → AI review → fixes → re-review → ready → human review (developer,
   business analyst) → fixes → merge (by whom) → deploy → cleanup. Offer the defaults; it will change as
   the project goes, so revise it whenever the owner says so.
e. **Who integrates:** per the strictness (CORE §3) — strict: humans merge, so the owner stays in the
   process; standard: the coordinator, the owner for risky changes; swarm: the coordinator on green
   checks and a confirmed verdict.
f. **Identity in artifacts:** not asked — always the owner's voice, first person, no mention of AI
   (§11); only the comment style is asked.
g. **Acceptance:** how the owner, QA or the client accepts work; re-acceptance after a requested change.
h. **Parallel work and resources:** may workers run in parallel; per-worker isolation of databases,
   ports, containers; shared resources to guard; serial identifiers (migration versions, decision
   numbers) and how they are allotted (§8).
i. **Budget:** usage caps, when to exceed them, which models are available (§7); time estimates and
   tracking where the strictness or the owner asks.
j. **Language** of the conversation and of artifacts.
k. **MCP and integrations:** detect the technologies (code host, tracker, design, database, hosting,
    docs, browser) and propose matching MCP servers; the owner decides what is connected and with which
    rights (production per the strictness, §1.4).
l. **Workers:** how they run (background sessions, subagents, worktrees), machine constraints (one GPU,
    one device, slow environment start-up).

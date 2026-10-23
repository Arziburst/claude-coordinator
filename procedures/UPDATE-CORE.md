# "Update the core"

Run only on the owner's command ("update the core", "обнови ядро", any wording). The project's own rules
(`PROJECT.md`, `BINDINGS.md`) are never rewritten by an update; they keep winning over the core's defaults.

1. **Which core.** Read the claude-coordinator commit recorded in `PROJECT.md` for `coordinator/core/`.
   No `coordinator/core/` (an older remote core) → the plan is to create it at the latest commit
   (MIGRATE-LAYOUT), shown in the report.
2. **What changed upstream:** clone claude-coordinator to a scratch folder; the commits and files since
   the recorded commit. The core is the whole repository except `.git/`, `.github/` and `CLAUDE.md` —
   `tests/` included: the self-test reads it, so a copy without it fails its own checks. `CLAUDE.md`
   never: it tells a session it is the coordinator, and Claude Code loads it into every worker that
   reads the core's roles (`selftest scripts` fails on it). A local copy that still has `examples/`
   (removed upstream) drops it with the update.
3. **Impact report to the owner, before changing anything:**
   - per change: what it does and what it changes in this project's work (briefs, review, models, init);
   - every line of `PROJECT.md` / `BINDINGS.md` that now overlaps or disagrees with the new core — the
     project rule still wins, the owner decides whether to keep, adapt or drop it;
   - each upstream change that conflicts with a local edit, and the proposed resolution;
   - **Settings the new core's checks fail:** `selftest hooks --settings` of the scratch clone on the worker
     safety file and on each of the coordinator's own settings files that holds the guard (one without it
     is "no guard: the owner's choice", CORE §1.16, never a FAIL; #223), before anything is merged — each FAIL is a change
     the project makes with the update, and each SKIP on the worker safety file a protection it does not
     use yet, offered to the owner (e.g. `COORD_PROTECTED_ROOT` not set: the working copy is not kept from
     workers' edit tools — the file gains the env value and the edit tools in the guard's matcher,
     TOOLKIT *Safety*). **Each SKIP on the coordinator's own settings files** is offered the same way,
     so the file is brought to the current guard matcher (e.g. a matcher without SendMessage: the
     coordinator's own messages to other sessions are not guarded, CORE §1.17 — the matcher gains the tools
     of the current settings example) — **except `COORD_PROTECTED_ROOT`**: it does not apply to the
     coordinator, which writes `coordinator/` inside the root (TOOLKIT *Safety*), so that SKIP is expected
     on its own files and not offered (#256). Auto mode refuses the coordinator's own edit of its settings
     ("Self-Modification"), so on the owner's yes the coordinator writes the **complete** new file in its
     scratch folder — from the target's current content, right before the command (another project may
     share it: the user's `~/.claude/settings.json`), the diff shown to the owner — and gives the owner one
     command to apply it — `! cp <prepared file> <target>` in the
     coordinator's prompt, or the same in their own terminal (PowerShell: `Copy-Item <prepared file>
     <target>`) — then re-runs `selftest hooks --settings <target>` in a **new** session (hooks load at
     start: the running session keeps the old guard);
   - **Breaking for project wrappers:** every upstream commit since the recorded one whose message has
     a line **starting** with `Breaking for project wrappers:` (`git log <old>..<new> --grep '^Breaking
     for project wrappers:'` — anchored, so a commit that only mentions the rule does not match), and for each script it names, every call to it in the project's coordination scripts
     (BINDINGS; `grep -rn <script name>`): the wrapper is fixed through the project's change path
     **before** the update is applied, or the first worker start after it fails. A wrapper that broke
     anyway (its fix needs a worker, or waits behind a red main line) does not stop the work: workers
     start through the core's start-worker directly, with the brief built as the wrapper would build
     it (BINDINGS *fallback*), until the wrapper's fix lands;
   - **Not done yet:** every row of the new core's [ONE-TIME.md](../ONE-TIME.md) with no line in
     `coordinator/CHECKLIST.md` for this project (a `project` row) or this machine (a `machine` row,
     by `hostname`), and every row whose newest line is `failed`. A setting is asked with its default
     first; a check is offered as "run now? yes/no".
   - **No `CHECKLIST.md` yet** (a project initialized before it existed): build it first. A step whose
     value `PROJECT.md` or `BINDINGS.md` already holds is listed as *found*, with the file and the line
     it comes from, and confirmed by the owner in one summary; everything else goes into *Not done
     yet*.
   - **No Settings block in `PROJECT.md`** (written before it existed): offer once to move its
     settings rows into the block at the top ([SETTINGS.md](SETTINGS.md)) — values unchanged, Source
     `owner` or `preset` as found, Since the date of the move — on the owner's yes.
   - **Core findings** ([CORE-FINDINGS.md](CORE-FINDINGS.md) §3): every `sent` row of
     `coordinator/CORE-FINDINGS.md` whose issue a commit of this update closes, and every local edit made
     as its workaround that the update makes unnecessary; after the update each is proven here and
     marked `fixed <commit>`, or goes back to `new`. A project that kept its core problems in another
     form gets the template's file, its rows converted, on the owner's yes.
   - **In auto mode** Claude Code's classifier may refuse step 4's changes to the coordinator's own
     configuration (the safety and settings files, `~/.claude/agents/`) as "Self-Modification", even a
     read next to them (#221). Say so in the report and ask the owner before step 4: they approve those
     changes in a mode that asks, or add an allow rule for them, or (a settings file) run the one command
     that applies the file the coordinator prepared (above); a refusal mid-update is raised, never
     worked around (CORE §1.16).
4. **On the owner's yes,** first **pause** every running session of this project (CORE §1.17), so none
   works under the old rules and scripts while they change: record each one's full session id, then
   each finishes its step, commits, pushes, reports and goes idle; one that does not is stopped by its
   short id (TOOLKIT *Pause and resume*). Then merge the upstream files into the local copy, keeping the agreed local edits,
   record the new commit in `PROJECT.md`, commit in `coordinator/`, and re-read the core. If the
   scripts changed, re-run the hook's self-test and `selftest hooks --settings` on the worker safety file and
   the coordinator's own settings files that hold the guard (SELFTEST step 2a). Always run `scripts/check-scripts` on the core copy
   and on the project's coordination scripts (the wrappers that call the core: BINDINGS), and one
   start-worker dry run on a real task (CORE §12a): an update can break a project wrapper that nothing
   runs until the next worker is due. Then the **full self-test** at the new commit
   ([SELFTEST.md](SELFTEST.md)), after every update (a `declined` CHECKLIST line: offered, never run silently): its branches in the state repository are the
   evidence that this commit works here; its CHECKLIST line names the commit. Then
   install the roles into `~/.claude/agents/` (TOOLKIT *Workers*, Roles) and refresh the core's skills — every
   `coordinator/core/skills/coord-*` copied over `coordinator/skills/`, a `coord-*` the core no longer has
   removed, the project's own skills untouched (CORE §12b), committed in `coordinator/` — automatic, no separate question. Changes to `PROJECT.md` the owner approved are committed in `coordinator/`.
   Run the one-time checks the owner said yes to; write a `CHECKLIST.md` line for every *Not done yet*
   and *found* row — `done`, `failed`, `declined` or `n/a` — so a declined step is never asked again
   unless the owner asks.
5. **Layout:** if `coordinator/` is not yet its own git repository hidden from the project's git
   ([INIT.md](INIT.md)), include the migration plan in the report and run it on the owner's yes:
   [MIGRATE-LAYOUT.md](MIGRATE-LAYOUT.md) (files tracked by the project's git leave it through the
   project's change path and stay on disk).
6. **Resume** every session paused in step 4, after the self-test: an idle one with a one-line
   "continue", a stopped one with `claude --bg --resume <full session id> "continue"` (TOOLKIT *Pause and
   resume*); each is told to re-read its brief's rules only where the update changes them.
7. **Journal** the update: the old and new commits, what the owner decided per item, the sessions paused
   and resumed.

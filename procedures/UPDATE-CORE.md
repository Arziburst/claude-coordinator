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
4. **On the owner's yes:** merge the upstream files into the local copy, keeping the agreed local edits,
   record the new commit in `PROJECT.md`, commit in `coordinator/`, and re-read the core. If the
   scripts changed, re-run the hook's self-test and `selftest hooks --settings` on the worker safety file and
   the coordinator's own settings files (SELFTEST step 2a). Always run `scripts/check-scripts` on the core copy
   and on the project's coordination scripts (the wrappers that call the core: BINDINGS), and one
   start-worker dry run on a real task (CORE §12a): an update can break a project wrapper that nothing
   runs until the next worker is due. Then the **full self-test** at the new commit
   ([SELFTEST.md](SELFTEST.md)), after every update: its branches in the state repository are the
   evidence that this commit works here; its CHECKLIST line names the commit. Then
   install the roles into `~/.claude/agents/` (TOOLKIT *Workers*, Roles) — automatic, no separate question. Changes to `PROJECT.md` the owner approved are committed in `coordinator/`.
   Run the one-time checks the owner said yes to; write a `CHECKLIST.md` line for every *Not done yet*
   and *found* row — `done`, `failed`, `declined` or `n/a` — so a declined step is never asked again
   unless the owner asks.
5. **Layout:** if `coordinator/` is not yet its own git repository hidden from the project's git
   ([INIT.md](INIT.md)), include the migration plan in the report and run it on the owner's yes:
   [MIGRATE-LAYOUT.md](MIGRATE-LAYOUT.md) (files tracked by the project's git leave it through the
   project's change path and stay on disk).
6. **Journal** the update: the old and new commits and what the owner decided per item. Tell running
   sessions to re-read their brief's rules only where the update changes them.

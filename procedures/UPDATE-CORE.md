# "Update the core"

Run only on the owner's command ("update the core", "обнови ядро", any wording). The project's own rules
(`PROJECT.md`, `BINDINGS.md`) are never rewritten by an update; they keep winning over the core's defaults.

1. **Which core.** Read `PROJECT.md`: *remote* or *local* core, and for a local one the recorded
   claude-coordinator commit.
2. **What changed upstream:** the commits and files since the recorded commit (remote core: since the
   commit this session last read). The core is every file a coordinator reads: `CORE.md`, `TOOLKIT.md`,
   `CONTRACT.md`, `roles/`, `procedures/`, the scripts.
3. **Impact report to the owner, before changing anything:**
   - per change: what it does and what it changes in this project's work (briefs, review, models, init);
   - every line of `PROJECT.md` / `BINDINGS.md` that now overlaps or disagrees with the new core — the
     project rule still wins, the owner decides whether to keep, adapt or drop it;
   - local core: each upstream change that conflicts with a local edit, and the proposed resolution;
   - what has to be installed (e.g. a new role into `.claude/agents/`, TOOLKIT *Roles*) and where.
4. **On the owner's yes:** local core — merge the upstream files into the local copy, keeping the agreed
   local edits, and record the new commit in `PROJECT.md`; remote core — re-read the core now. Install
   roles: into `~/.claude/agents/` on this machine, or into the project's `.claude/agents/` through the
   project's change path (§1.1). Changes to `PROJECT.md` the owner approved are committed in `coordinator/`.
5. **Layout:** if `coordinator/` is not yet its own git repository hidden from the project's git
   ([INIT.md](INIT.md)), include the migration plan in the report and run it on the owner's yes:
   [MIGRATE-LAYOUT.md](MIGRATE-LAYOUT.md) (files tracked by the project's git leave it through the
   project's change path and stay on disk).
6. **Journal** the update: the old and new commits and what the owner decided per item. Tell running
   sessions to re-read their brief's rules only where the update changes them.

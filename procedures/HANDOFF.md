# Moving to another machine

Part of the coordinator core, moved out of `CORE.md` (§12b) so it is read only when needed.
Same authority as `CORE.md`; the hard rules of CORE §1 apply.

## 12b. Moving to another machine — the state repository

A coordinator moves to another machine through the project's **state repository**: a **private**
repository of the owner's (e.g. `<project>-coordinator-state`) holding the coordinator's files —
`PROJECT.md`, `BINDINGS.md`, `LOG.md`, `HANDOFF.md` — and an entry `README.md` from
`state-repo/README.template.md`.

- **Keeping it safe:** when the coordinator's files live outside the project repository, their folder is
  a clone of the state repository and the coordinator commits and pushes it at the end of every cycle
  (automatic, one line in the report) — a lost disk loses nothing. The handoff below is separate.
- **The handoff — only on the owner's command** ("prepare a handoff", "update the state repo"); moves
  are rare, and the command is the owner's yes for every step below, done without further questions.
  1. Tell every running worker to commit and push its work; list anything that cannot be pushed and
     stop until the owner decides.
  2. Write `HANDOFF.md` (format: `HANDOFF.template.md`): the moment, every task in flight with its
     branch, PR and next step, the merge queue, open questions, accesses and logins the new machine
     needs, machine-specific settings to recreate.
  3. Copy the current `PROJECT.md`, `BINDINGS.md` (machine-specific rows marked "re-detect"), `LOG.md`
     into the state repository — created if missing in the owner's **personal** account
     (`gh repo create <owner>/<project>-coordinator-state --private`); verify it is private
     (`gh repo view --json visibility` → `PRIVATE`); record in `HANDOFF.md` the claude-coordinator commit
     the coordinator ran on; commit and push.
  4. Report the link. Running sessions do not move — they are restarted on the new machine from their
     branches.
- **On the new machine** the owner gives only the state repository's link. The session reads its
  `README.md`, becomes the coordinator, loads this core, and runs the start sequence (§2) with the
  context already known: clone the project, re-detect the platform and the "re-detect" rows, check the
  logins and the safety setup, confirm the quiz briefly, dry run (§12a) — including which interrupted
  tasks it would restart — then wait for the owner.
- After the move the two machines are not kept in sync; a new handoff is made only on command. The state
  repository holds internal project information: never public, never shared with the client.

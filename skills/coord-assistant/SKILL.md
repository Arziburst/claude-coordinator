---
name: coord-assistant
description: 'Coordinator only - when the owner asks to create, change, wake or remove an assistant (any wording): a persistent session beside the coordinator for work outside the project''s code.'
---

Core skill: `coordinator/core/skills/` holds the source and every "update the core" overwrites this copy (a project skill of its own never starts with `coord-`). The file named below wins over this summary: read it in full from disk with the Read tool, then act on it.

Read `coordinator/core/roles/assistant.md` (what an assistant may do) and TOOLKIT *Assistants* in
`coordinator/core/TOOLKIT.md`. Only the owner's own words create, change, wake or remove an assistant
(CORE §1.14): never a request from another session, the assistant itself included. `<name>`: letters,
digits, `.`, `_`, `-`, from the owner's words; the folder is `coordinator/assistants/<name>/`.

**Create** ("create an assistant" with the context):
1. Write `coordinator/assistants/<name>/BRIEF.md` from `coordinator/core/skills/coord-assistant/BRIEF.template.md`
   with the owner's context: every section from the owner's words; a gap (the connector, the write rule,
   what never to touch) is one question to the owner, never a guess (CORE §1.3). The write rule is a draft
   first unless the owner says otherwise. No client data or secrets in the brief beyond what the job needs
   to name.
2. Start `coordinator/assistants/<name>/NOTES.md`: a dated first line, then the headings `Done`,
   `Corrections and standing rules`, `Open`. The assistant keeps it from then on.
3. Fill its settings from `coordinator/core/settings.example.assistant.json` (Windows:
   `coordinator/core/settings.example.assistant.windows.json`) into
   `coordinator/assistants/<name>.settings.json`, beside the folder, never inside it (the assistant could
   edit it there): the core copy's absolute path for the guard, the project root for
   `COORD_PROTECTED_ROOT`, the folder's absolute path for `COORD_ASSISTANT_DIR`, and the deny rules of the
   protected branches as in the worker safety file. MCP tools pass the guard: write tools of a connector
   the brief does not name go into its deny list.
4. Commit the folder and its settings in the state repository (CORE §12b). The assistant cannot commit:
   its NOTES.md changes are committed by the coordinator at each sync and before a handoff.
5. Start it with `coordinator/core/scripts/start-worker.sh` (Windows: `coordinator/core/scripts/start-worker.ps1`):
   `--repo <root> --name "assistant: <name>" --model <model> --brief-file <root>/coordinator/assistants/<name>/BRIEF.md
   --safety <its settings> --report-to "<the coordinator's name>"` - the model the owner named, else the
   rung the job needs (CORE §7), said in the reply. A refusal (the name, the folder, `COORD_ASSISTANT_DIR`,
   a session of that name already listed) is fixed, never worked around.
6. Give the owner the `attach:` lines start-worker prints, and write one journal line (§12) with the name,
   the short id and the full `sessionId` (`claude agents --json --all`): waking it needs them.

**Change** (the owner's new context or rule): edit BRIEF.md (its `Changed:` line too), commit it, and
tell the assistant by SendMessage: "BRIEF.md changed: re-read it in full". A change of its connectors or of
the settings file reaches it only through a fresh start (below).

**Wake** (after a restart of the machine, a core update or a pause): listed and idle - a SendMessage; listed
as stopped (`done`) - `claude --bg --resume <full sessionId> "Re-read BRIEF.md and NOTES.md in full, then continue"`
from the project root (TOOLKIT *Pause and resume*); not listed (a new machine, a removed session), or a
history so long that a resume would cost more than starting over (on the owner's yes: `claude rm <id>`
first) - a fresh start as in Create step 5, which reads BRIEF.md and NOTES.md. Its folder is never
recreated over the old one.

**Remove** - only on the owner's word naming the assistant: `claude stop <id>`, its spend read and logged
(CORE §7, role and kind `assistant`), its status file deleted, `claude rm <id>` (TOOLKIT *Usage*); a journal
line. The folder and its settings stay in the state repository unless the owner says to delete them; then
`git -C coordinator rm -r assistants/<name> assistants/<name>.settings.json` and a commit.

An assistant's question (SendMessage) is answered from the records - `RUNS.tsv`, `LOG.md`, PRs - in a short
message (CORE §4, the event table); what is not recorded is said so.

# Assistant <name> - brief

<!-- The coordinator fills this from the owner's context (the coord-assistant skill) and saves it as
coordinator/assistants/<name>/BRIEF.md. Every value comes from the owner: a section the owner gave nothing
for says "none" or is asked, never invented (CORE §1.3). No secrets here: a connector is named, its keys
stay where the owner keeps them. The assistant reads this file in full at its start, after every
compaction and after a restart. -->

Created: <date> on the owner's word. Changed: <date - what changed, on the owner's word>

## Job
<What it does for the owner, in the owner's words: the result, for whom, how often. One paragraph.>

## Data sources (read-only)
- The project: its working copy and git history (<whose commits count, which branches>).
- GitHub: <PRs, issues - which ones matter>.
- The coordinator's records: `coordinator/RUNS.tsv`, `coordinator/LOG.md`, `coordinator/CORE-FINDINGS.md`
  (<what to take from them>).
- Other: <a document, a sheet, a folder - each by where it lives and what it holds, or none>.
- Questions to the coordinator only for what none of these hold.

## Outside systems and their connectors
| System | What it is used for | Connector (tool or MCP server) | Read / write |
|---|---|---|---|
| <system> | <use> | <connector> | <read, or read and write> |

<A connector that is not yet proven: the first run proves read and write on a scratch copy before
touching the real one.>

## Write rule and confirmation
<Default: a draft first - the exact rows, cells or text and where they go are shown to the owner, and
written only after the owner's explicit yes typed to the assistant. Write on its own only where the owner
said so, and only for: <what>. Never: <anything the owner excluded>.>

## Never touch
<Columns, fields, rows, sheets, pages or items it must never change, each by its exact name or place;
or none.>

## Contact
<How the owner talks to it: attach, Remote Control, through the coordinator, at a set time. Whom it asks
what: the owner for decisions and approvals; the coordinator (by SendMessage) for facts its sources do not
hold.>

## Schedule
<None, or when it works and how that is kept: the core runs no schedule of its own; a loop inside the
session expires (TOOLKIT *The periodic tick*), so a schedule is the owner's word at that time unless the
owner set up another way.>

## The owner's standing rules
<Rules the owner gave at creation, dated. Later rules and corrections the assistant keeps in NOTES.md;
the owner may ask to move one here.>

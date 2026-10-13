# Core findings — from every project to the maintainer, and back

Part of the coordinator core, read when a core finding is recorded, sent or closed. Same authority as
`CORE.md`; the hard rules of CORE §1 apply (§1.9 and §1.13 above all: an issue in claude-coordinator is
public).

A project's coordinator is also a tester of the core: what breaks in real work is the evidence the core
needs. This procedure turns it into one format, sends it to the maintainer as an issue, and proves each
fix on the project after the next update.

## 1. Record — at the moment

`coordinator/CORE-FINDINGS.md` (from [CORE-FINDINGS.template.md](../CORE-FINDINGS.template.md), created
at init) gets a row **the moment** a trigger happens, before any workaround:
1. a core rule could not be followed (it blocks all progress, or contradicts another rule);
2. a core script behaved wrongly (an unexpected exit, a wrong verdict, a refusal of valid work);
3. a safeguard or a check silently did not work (it ran and did not protect, or did not run);
4. the core had no step for a real situation;
5. a role could not do what the core requires of it.

**Core or project?** Would the same core rule, script or template fail the same way in any project? Then
it is a core finding. Only this project's wrapper or setting broke → a project issue. Both (the project
fixes its setting, the core lacks the warning or the check) → both, each in its place.

Workers, leads and verifiers report a suspected core problem in their report's `core_findings:` list
(roles/worker.md); the coordinator decides and writes the row. When a task ends it asks itself:
did any core rule, script or check fail us in this task? (CORE §4).

## 2. Send — an issue in claude-coordinator

How a project sends is the owner's choice at init (INIT 3.1, question 11; `PROJECT.md` *Settings*,
**core reports**): *automatically* — filed the moment the row is written · *show me each one first* · *no —
keep them here, I pass them on by hand*.

**The report has fixed fields only** — nothing from the project goes into a public issue:

```
Title: <core file or script>: <one-line summary>
Core: <the local core commit> (upstream main <sha> when filed)
Where: <core file, section or script; the role>
Trigger: <1-5 above>
Environment: <OS and version>, claude <v>, git <v>, gh <v>, PowerShell <v> / bash <v>
Ran in: <the tool that ran it: Bash (Git Bash / bash / zsh <v>) or PowerShell <v>>; <CLI / desktop app / IDE>;
        <the session's role, model and effort>
What happened: <in the core's terms; no project names, paths, URLs, people or code>
Evidence: <the core command, its exit code and its error lines; paths as <path>, the project as <project>>
Expected: <what the core says should happen>
Proposal: <optional>
Signature: <core file or script>: <the error's key words>
```

Before filing, in this order:
1. **Fixed upstream?** The local core is behind upstream and a closed issue with the same signature is
   fixed in a newer commit (`gh issue list -R Arziburst/claude-coordinator --state closed --search
   "<signature>"`) → no issue; the row becomes `fixed upstream <commit>` and the owner hears "update
   the core".
2. **Already reported?** An open issue with the same signature → a comment `+1: core <commit>,
   <environment>` instead of a new issue; the row gets that issue's number.
3. **Rate:** at most three new issues a day from one project; the rest wait for the next day.
4. **File** with the owner's own gh login, the title prefixed **once** with `[core-report] ` (the
   `Title:` line above has no prefix, and the body does not repeat the title): `gh issue create -R
   Arziburst/claude-coordinator --title
   "[core-report] <Title>" --body-file <report>`. The title prefix is enough: claude-coordinator's own
   workflow adds the `core-report` label (an outside account cannot set labels). The row becomes `sent
   #<issue>`.

*Show me each one first*: the owner sees the report and says yes or no per issue. *No*: the
coordinator prints the same reports for the owner to pass on by hand (rows `discussed` → `sent <date>`).
No gh or no access: printed the same way. Customer data and secrets never go into a report, in any mode
(CORE §1.13).

## 3. Close the loop — after an update

"Update the core" (UPDATE-CORE step 3) lists every `sent` row whose issue is closed by a commit the
update brings, and every local edit made as a workaround that the update makes unnecessary. After the
update each is proven on the project — through the self-test step that covers it where there is one —
and marked `fixed <commit>`; one still broken goes back to `new` with the new evidence, and is filed
again with a reference to the old issue.

## 4. The maintainer

Issues labelled `core-report` are triaged in claude-coordinator: reproduce, fix in a PR that names the
issue (`Fixes #<n>`), close it with the fixing commit, and keep project details out of the fix. A change
to a script's arguments or output carries its `Breaking for project wrappers:` line (README *Changing the
core*).

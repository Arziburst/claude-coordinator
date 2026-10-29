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

**The core's own coordinator** (its project is claude-coordinator itself, #148): a core finding is a
task of its own project — recorded here, then filed as an ordinary issue of the project (no
`[core-report]`, nothing "sent to the maintainer": that is this coordinator) and planned like any
other task.

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

**The signature.** A finding a core script or check produced gets its signature from the script, never
from a model: `<core>/scripts/report-issue.sh signature --source <script or core file> --step <step> --exit
<code> --error "<its first error line>"` (Windows: `report-issue.ps1 signature -Source … -Step … -Exit …
-ErrorText …`) prints one line `<source>: <step>: exit <code>: <words>` — the error lower-cased, paths,
drive letters, URLs, hex ids, numbers, dates and quotes replaced by fixed tokens, at most 120 characters —
so the same error on a thousand machines gives one signature, and one issue. The line goes into a public
issue, so it is safe by default: after an unquoted path start (a drive, UNC, `/`, `~/`, `./`, `../`,
`.\`, `..\`, `~\`, a `file:` URL, an scp-style remote) the rest of the line is that one token, since a
space in a path cannot be told from words; any other word holding a `/` or `\` (a repository, a branch, a
relative path) is a path token, unless it is a core path (under the core's scripts/, procedures/, roles/,
skills/, tests/, or a core root file); any word with an `@` and a `Name <a@b>` pair are an e-mail token;
an IP address with its port and a `word.word` that is no core or coordinator file name (`PROJECT.md`,
`BINDINGS.md`, `RUNS.tsv` stay), number, version or abbreviation (`e.g.`) are a host token. **Not
detected:** a name written as a plain word — a login after "denied to", a one-word host, a company or
project name. So the coordinator reads the printed signature before filing and never files one that
holds such a name (as with the whole report: nothing from the project goes into a public issue). A
model-written signature (`<core file or script>: <the error's key words>`) only for a finding no script
produced.

Before filing, in this order — every check runs through **one script**, `<core>/scripts/report-issue.sh
file` (Windows: `report-issue.ps1 file`, the same lines and exit codes), the one path for every channel
that files to claude-coordinator (this section, a self-test FAIL from the core, the retro's proposals,
the Claude Code format check below; #338): `report-issue.sh file --repo Arziburst/claude-coordinator
--title "[core-report] <Title>" --body-file <report> --signature "<signature>" --keywords "<3-6 key words
of the problem>"` (`--dry-run` first prints what it would do and changes nothing; every gh call it makes
is read-only but the new issue, the reaction and the comment):
1. **Already reported?** An open issue with the same signature (the script finds an issue whose body holds
   the exact `Signature:` line — an exact-phrase search: an apostrophe in a git error otherwise finds
   nothing; an open one is checked first and wins over a closed one, so a reported regression is a repeat,
   never `FIXED UPSTREAM`) → a 👍 (+1) reaction on it from the owner's account instead of a new issue or a
   comment (`REPEAT #<n>`, exit 0; a reaction already there from this account is not added twice); the row
   gets that issue's number. A comment only with something new — another OS, version, scenario or
   evidence: `--comment-file <file>` holding `+1: core <commit>, <environment>` and the new fact.
2. **Fixed upstream?** The local core is behind upstream and a closed issue with the same signature is
   fixed in a newer commit — no open match, and a closed issue holding the exact `Signature:` line (the
   same exact-phrase search), closed as completed: the script prints `FIXED UPSTREAM #<n>` (exit 3; of
   several such issues the newest, the highest number) → no issue; the row becomes `fixed upstream
   <commit>` and the owner hears "update the core". Closed as not planned is no fix: the checks go on. On
   `FIXED UPSTREAM` the coordinator compares the fix's commit with the project's core commit: the core
   lacks it → "update the core"; the core already holds it → the bug came back: the same command again
   with `--regression` (Windows `-Regression`), which files one new issue, the title as given, its body
   holding `Regression of #<n>` (the same newest `#<n>`) and still ending with the `Signature:` line;
   nothing is written on `#<n>`. One issue per regression: every other project finds it open and reacts
   (1).
3. **The same problem in other words?** No signature match → a keyword search (`--keywords`, else the
   title; title and body, open and closed, the last 90 days, at most 5 candidates). Any candidate not read
   yet → `CHECK #<a> #<b> …` with each title, nothing filed (exit 4). The coordinator reads each one and
   decides same or different: the same problem → a 👍 reaction there (a comment only with something new),
   the row gets its number; none the same → the same command again with `--checked <a>,<b>`, and the new
   issue names them (`Checked: #a, #b`).
4. **Rate:** at most three new issues a day from one project; the rest wait for the next day. Only new
   issues count — a repeat (a reaction, or a comment with something new) is no new issue.
5. **File** — `report-issue file` itself files when nothing above matched, with the owner's own gh login,
   the title prefixed **once** with `[core-report] ` (the `Title:` line above has no prefix, and the body
   does not repeat the title); the body ends with the script's own `Checked:` (when it read candidates)
   and `Signature: <signature>` lines, so the next project finds it by exact match. It prints `FILED #<n>`.
   The title prefix is enough: claude-coordinator's own workflow adds the `core-report` label (an outside
   account cannot set labels). The row becomes `sent #<issue>`.

**The Claude Code format check** (#143, where it files): a format the core reads that moved after a
Claude Code update is filed through the same script with a fixed, script-built title that is also its
signature — `[claude-format] <version>: <record> <field>` (the Claude Code version, the record and the
field that moved; `--title` and `--signature` the same line). The first project files it; every other
project finds it by exact match and adds a 👍 reaction (a comment only with something new), never a
second issue.

*Show me each one first*: the owner sees the report and says yes or no per issue (the checks above run
first with `--dry-run`, so the owner also sees whether it is a new issue or a repeat). *No*: the
coordinator prints the same reports, the title already prefixed `[core-report] ` (the label workflow
needs it), for the owner to pass on by hand (rows `discussed` → `sent <date>`).
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

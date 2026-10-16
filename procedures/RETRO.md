# The weekly retro — the coordinator measured, and improved

Part of the coordinator core, read when the retro runs. Same authority as `CORE.md`; the hard rules of
CORE §1 apply — §1.11 (a proposal changes nothing without the owner's yes) and §1.13 (an issue in
claude-coordinator is public) above all.

The owner's goal for the coordinator: code written **cheaper, faster, with higher quality, more
predictably and more stably** than plain distributed sessions. Once a week the retro measures each of
the five on this project, this week against the previous one, turns the numbers into at most three
proposals, and — as the owner chose at init — sends an anonymous summary to the core's maintainer.

## 1. When

- **Weekly, by itself.** The retro is due when the *Settings* row **last retro** in `PROJECT.md` names a
  week before the last complete one (or none): checked at session start and with the daily sync (CORE §4,
  the events), and on the tick where autopilot runs one (CORE §9). A session-scoped cron cannot carry a
  weekly job (it expires after 7 days, TOOLKIT *The periodic tick*), so the due check is the schedule.
  It runs once per week; a week already done is not run again unless the owner asks.
- **"Retro"** from the owner, in any wording ("ретро", "retrospective"), any time: the last complete
  week, or the week the owner names (`--week <a day of it>`; the current week, still partial, with
  today's date).
- Never before the init quiz is complete (CORE §1.12). Until the `self-improvement` setting has an
  answer (a project from before it: the one-time step, ONE-TIME), the retro runs as `only me`.

## 2. The steps

1. **Run** `scripts/retro.sh coordinator/RUNS.tsv` from the core copy (Windows: `powershell
   -NoProfile -ExecutionPolicy Bypass -File coordinator/core/scripts/retro.ps1 coordinator/RUNS.tsv`;
   TOOLKIT *Usage*). It reads the run log, `LOG.md`, `ESCAPES.tsv`, `ROUTING.md` (its `## Kinds` map) and
   `PROJECT.md` (its *Worktree roots*) next to it, and the project's transcripts of both weeks through
   `session-insights --skip-tests --project <root>|<worktree roots>|<root>/.claude/worktrees`; it prints
   the local report and sends nothing. A real run log is read as it is written: a cost cell by its
   leading number (`0.0648 prices`), a result by its first word (`done`, `pass` = approved); a result no
   word explains is listed as `unknown result: <value> ×<n>` — fix the log or the habit behind it.
2. **Read the report** — five axes, this week and the previous one:
   - *cost* (dollars at API list price, CORE §7a *The unit*): tasks, merged tasks, the median cost per
     task, the total (the tasks' and the coordinator's own lines), the cost per merged task;
   - *speed*: the medians of time to ready and of work, and — **apart, never mixed into the others** —
     the owner wait (its median, and the tasks still waiting);
   - *quality*: the rework, escalation and failure rates (of the tasks with runs), escaped bugs and per
     10 merged tasks (CORE §12), and the same rates per kind;
   - *predictability*: per measure (cost, work, time to ready) how many tasks had a forecast, the share
     inside its range and the median of actual over forecast. The forecast is the estimate the run log
     logged at the start (`estimate` for cost, `estimate_time` for work, CORE §7: a range `lo-hi`, its
     midpoint for the ratio; one number `n`, in range from `2n/3` to `3n/2` — symmetric on a log scale and close to a range's 25th–75th band), counted as `_logged`; else it
     is rebuilt as `run-stats` gave it before the task (the 25th–75th percentile, CORE §7a), counted as
     `_rebuilt`; time to ready is always rebuilt;
   - *stability*: failed runs, guard blocks and deny rules, blocks worked around, guard false positives
     (§5), guard errors (the guard's own hook failing or timing out instead of blocking), other
     refusals, tool errors and their rate, cache rewrites per task, minutes waited on a person, rereads.
   `—` is too little data (under 3 tasks, merged tasks or forecasts; under 100 tool calls; no
   transcripts, journal or escapes file): no proposal rests on a `—`. `around` is worth a look, never a
   finding by itself (TOOLKIT *Usage*: a correct next step can name the same path).
   **Test sessions are already out:** a session whose name has `probe`, `selftest` or `self-test` as a
   word before its first colon (`#0 probe: …`, `probe: …`, `selftest`), a self-test task `#st<n>`, or a
   session started inside a `coordinator-selftest` sandbox, with its subagents; and in the run log the
   rows of a task `st<n>` or `0` or a kind or role naming probe or self-test. A product task whose title
   only mentions a self-test (`#14 worker: Self-test page for the kiosk`) is real work and stays. A test the
   coordinator ran on purpose under another name (a deliberate block) is subtracted by hand and said so.
3. **Write the top three proposals** — fewer when fewer stand out, none when nothing does. Each has:
   - **evidence** — the numbers, this week against the previous one;
   - **expected gain** — in dollars per task, minutes per task, or points of the rework rate;
   - **risk** — low / medium / high, and which axis could get worse;
   - **the concrete change** — a `PROJECT.md` row, a `ROUTING.md` pin, a `BINDINGS.md` command, a brief
     or contract habit; for the core, a CORE section, a script or a role;
   - **level** — `project` (this project's layers) or `core` (would help every project, CORE §10).
   Ranked by gain against risk.
4. **Project-level proposals** go to the owner in the coordinator's next message, short, in the owner's
   language; each waits for the owner's yes (§1.11) and then goes into its layer (CORE §10), journaled.
5. **Core-level proposals** become `[self-improvement]` proposal issues (§4) **only in `send` mode**; in
   `show me first` each is shown and filed on the owner's yes; in `only me` they stay in the journal.
6. **The summary** (§3), per the mode: `send` — filed; `show me first` — the body shown, filed on the
   owner's yes; `only me` — nothing leaves the machine.
7. **Book-keep:** one journal line — `retro week of <date>: cost <median>/task, ready <median> min,
   rework <rate>, in range <cost share>, guard blocks <n>; proposals <n> (project <n>, core <n>);
   summary filed #<n> / shown / kept local` — the *Settings* row **last retro** set to the week, a commit
   in `coordinator/`.

**The first week** after the setting is answered runs as `show me first` whatever the answer: the owner
sees the first summary, then chooses the mode from then on — `send`, `show me first` or `only me` —
recorded in *Settings* (`owner, <date>`).

## 3. The summary issue

- **Body:** exactly what `scripts/retro.sh coordinator/RUNS.tsv --public --id <id>` prints — a fixed
  template filled with numbers and allowlisted names, checked by the script before it prints anything.
  The coordinator never edits it by hand; a body edited anyway (by the owner, for any reason) passes
  `retro.sh --check-public <file>` before it is filed.
- **Title:** `[self-improvement] summary <id> week of <YYYY-MM-DD>`.
- **One per project-week:** first `gh issue list -R Arziburst/claude-coordinator --state all --search
  "\"summary <id> week of <date>\" in:title"`; one found → nothing new is filed.
- **File** with the owner's own gh login: `gh issue create -R Arziburst/claude-coordinator --title
  "<title>" --body-file <file>`. claude-coordinator's workflow adds the `self-improvement` label to
  every title starting `[self-improvement]` (an outside account cannot set labels).

## 4. Proposal issues — core level, `send` mode

- **Body:** the template below, filled only with the anonymous id, the week, the axis and measure
  names and their numbers from the summary, the risk, the core file it changes, and two lines in the
  core's own terms — no fact of the project. `retro.sh --check-proposal <file>` must pass before it is
  filed: every table cell allowlisted, the core file a file of the core, and the two text lines with no
  path outside the core, no link, address, task number or the project folder's name.

```
<!-- self-improvement proposal, format 1 -->
**Coordinator self-improvement: proposal** from one project's weekly numbers, in the core's own terms: no code, file names, paths, branches, task text or names of the project.

| Field | Value |
|---|---|
| project | <id> |
| week of | <YYYY-MM-DD> |
| signature | <axis>:<measure>:<core file name> |
| axis | <cost, speed, quality, predictability or stability> |
| measure | <a measure of the summary> |
| week | <its value this week> |
| previous | <its value the week before> |
| risk | <low, medium or high> |
| core file | <the core file it changes, e.g. scripts/hooks/safety-guard.sh> |

Change: <one paragraph: what changes in the core, in the core's terms (CORE §, script, role)>
Expected gain: <numbers: dollars or minutes per task, rework points, blocks per week>

A proposal, not a bug report: the maintainer acts on it only after the owner's discussion and yes.
```

- **Title:** `[self-improvement] proposal: <axis> <measure> (<core file name>)`.
- **Already proposed?** `gh issue list -R Arziburst/claude-coordinator --state open --search
  "\"<signature>\" in:body"` — one found → a comment `+1: project <id>, week of <date>, <measure> <week
  value> (previous <value>)` instead of a new issue.
- **Rate:** at most three proposal issues per project-week (the top three), plus the one summary.

## 5. Guard false positives

When the owner says a guard block was not needed ("that push was mine", "the block was wrong"), the
coordinator journals at once: `<date> guard false positive: <the guard's reason as the block printed
it>` (a path as `<path>`). The retro counts these lines per week (dated by their own date, else the
last date above them). A block the owner confirms as right gets no line; a block the coordinator only
suspects is not one.

## 6. What leaves the machine

Only what the script's template holds: aggregate numbers; the core's own kinds (`trivial`,
`ordinary`, `hard`, `hardest` — CORE §7's table; a project's own kind by its `ROUTING.md` `## Kinds` map,
one-time step `kinds-map`; an unmapped kind as `other`); the guard's reasons and the
refusal sources as fixed keys; the anonymous id; the week's dates. Never a project name, file name,
path, branch, task text, code, commit message, session name, model or tool name. It is enforced by the
script — a fixed template and a check that fails on any line outside it, any cell outside the allowlist,
a `/` or `\`, or the project folder's name — not by judgement. The local report and `session-insights
--detail` never leave the machine.

**The anonymous id** is `retro.sh --new-id` (12 random hex digits), made once when the setting is
answered and kept in `PROJECT.md` *Settings*; it is never derived from a name, so summaries of one
project can be compared across weeks and nothing else.

## 7. The maintainer

Issues labelled `self-improvement` are data and proposals, **not bug reports**: the maintainer acts on
one only after the owner's discussion and yes, through the core's own change path (CORE §10). Core bugs
keep their own channel (`[core-report]`, [CORE-FINDINGS.md](CORE-FINDINGS.md)).

# The retro — the coordinator measured, and improved

Part of the coordinator core, read when the retro runs. Same authority as `CORE.md`; the hard rules of
CORE §1 apply — §1.11 (a proposal changes nothing without the owner's yes) and §1.13 (an issue in
claude-coordinator is public) above all.

The owner's goal for the coordinator: code written **cheaper, faster, with higher quality, more
predictably and more stably** than plain distributed sessions. When the owner asks, the retro measures
each of the five on this project, a week against the previous one, turns the numbers into at most three
proposals, and — as the owner chose at init — sends an anonymous summary to the core's maintainer. On
the owner's word it also files the project's anonymous report for the core's own retro (§8).

## 1. When

- **Only when the owner asks** — it never runs by itself (the owner's decision, #242: a weekly due
  check was never acted on). The *Settings* row **last retro** in `PROJECT.md` records the last week
  done.
- **"Retro"** from the owner, in any wording ("ретро", "retrospective"), any time: the last complete
  week, or the week the owner names (`--week <a day of it>`; the current week, still partial, with
  today's date).
- Never before the init quiz is complete (CORE §1.12). Until the `self-improvement` setting has an
  answer (a project from before it: the one-time step, ONE-TIME), the retro runs as `only me`.

## 2. The steps

1. **First the missing rows** (#332): `scripts/runs.sh check --log coordinator/RUNS.tsv --root <project
   root> --self <the coordinator's session id>` from the core copy (Windows: `scripts/runs.ps1 check -Log
   … -Root … -Self …`; TOOLKIT *Usage*); each run it lists as `MISSING` gets its row with `scripts/runs
   add` (CORE §7) before the retro reads the log. Then **run**
   `scripts/retro.sh coordinator/RUNS.tsv` from the core copy (Windows: `powershell
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
     `_rebuilt`; time to ready is always rebuilt. `scripts/run-stats <RUNS.tsv> --ratio --model <m>` is the
     same median of actual over the logged estimate, per model over all its tasks — the factor a thin
     history's guess is scaled by at the task start (CORE §7a);
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
- **Already proposed?** The same path as a core finding (CORE-FINDINGS.md §2, #338): `<core>/scripts/report-issue.sh
  file --repo Arziburst/claude-coordinator --title "<the title>" --body-file <file> --signature
  "<signature>" --keywords "<axis> <measure> <core file name>"` (Windows: `report-issue.ps1 file`), the
  signature the table's `<axis>:<measure>:<core file name>`; it searches open and closed issues for it
  as an exact phrase (`"\"<signature>\" in:body"`) and adds the body's last line `Signature: <signature>`
  to a new one. One found open → a 👍 (+1) reaction from the owner's account instead of a new issue
  (`REPEAT #<n>`); the comment `+1: project <id>, week of <date>, <measure> <week value> (previous
  <value>)` only when it adds something new (`--comment-file`). Closed as completed (`FIXED UPSTREAM`) →
  no new proposal while the project's core lacks that change ("update the core"); the core already holds
  it and the measure is still bad → the same command again with `--regression`, as for a finding (one new
  issue naming the closed one). Closed as not planned goes on to the check. `CHECK` → the candidates read
  and decided as there, then `--checked`.
- **Rate:** at most three proposal issues per project-week (the top three), plus the one summary; a repeat
  (a reaction) is no new issue and does not count.

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

## 8. The retro report for the core

One anonymous report per project of how useful the core was **since its last report** (the first one:
since the coordinator was installed): a fixed template the script fills with the numbers and a checker
guards, the coordinator adds only short anonymous lines, and it reaches claude-coordinator as one issue.
The core's own retro then judges every feature from real use (#142, #303). Like the issues of §7, it is
data, not a bug report.

- **When:** only on the owner's word to the project's coordinator ("a report for the core's retro", in
  any wording) — never by itself (#242), and never before the init quiz is complete (CORE §1.12). The
  first one is offered once, at the next "update the core" after the core added it (one-time step
  `core-retro-report`, ONE-TIME); a `declined` there is never offered again, and later reports come only
  on the owner's word. The `self-improvement` setting does not apply: this report is always shown first.

**The steps:**

1. **Generate** `coordinator/core/scripts/retro.sh coordinator/RUNS.tsv --core-report --id <id>`
   (Windows: `powershell -NoProfile -ExecutionPolicy Bypass -File coordinator/core/scripts/retro.ps1
   coordinator/RUNS.tsv -CoreReport -Id <id>`), into a file outside the project's git. `<id>` is the
   *Settings* row **Self-improvement id** (none yet: `retro.sh --new-id`, recorded there). The period runs
   to today (UTC) from `--since <YYYY-MM-DD>` when the owner names a start, else from the day after the
   end of the *Settings* row **Last core report**, else from the first line of `coordinator/CHECKLIST.md`.
   The script fills: the core commits of the period (the CHECKLIST commit in use on its first day, then
   those of its lines in the period; else the commit in the *Settings* row **Core**), the period and the
   id; the profile it can read (strictness, spend level and work mode from *Settings* — only the
   vocabulary word the Value starts with, `swarm` / `standard` / `strict`, `lean` / `balanced` /
   `thorough`, `by task` / `batch`, never the rest of the Value; none: `<fill>` —, and the machine's OS);
   the five axes over the period, computed as the weekly report computes them (§2); the run log's rows of
   the period by role (no task rows, probes or self-tests); the guard's reasons and the refusal sources of
   the period's transcripts (blocks, retried, worked around, changed, stopped — through session-insights,
   as in §2 step 1); `CORE-FINDINGS.md`'s rows dated in the period by their status (`fixed upstream` counts as
   fixed) and the local edits of the core copy (the *Settings* row **Core**); and one row per feature id
   of the core's `FEATURES.md`, generated, never typed by hand. Every cell left to the coordinator is
   `<fill>`.
2. **Fill** each `<fill>` with a short anonymous line from the journal, the run log and the coordinator's
   own knowledge of the period:
   - *stack class* — a class, not a product, exactly one of `game engine`, `web`, `mobile`, `CLI`,
     `library`, `data`, `other`; *solo or team* — `solo` or `team`; a strictness, spend level or work mode
     left `<fill>` gets its vocabulary word (as above); every Profile cell holds only a word of its
     vocabulary (the OS: `windows`, `macos` or `linux`);
   - per feature: **Used** and **Trusted** (its numbers or its result were relied on) — **only** `yes`,
     `no` or `unknown`, never `n.a.` or `n/a` (the path and the file-name rules below would refuse them);
     **How often** (`every task`, `every session`, `weekly`, `once`, `never`); **Decision changed** — one
     short line, or `none`; **Friction** — one short line, or `none`;
   - the top three that helped most and got in the way most (`none` where there are fewer), and the
     proposals, one per row, at most three (`none` when there is none).
   A line never names a project, product, client or person, a path, a file other than the core's own, a
   branch, code, a commit, a task number of the project or task text (an issue `#<n>` of claude-coordinator
   may be named); it holds no link, e-mail or `@handle`, and at most 160 characters. A dotted word such as
   `e.g.` reads as a file name — write "for example".
3. **Check** `coordinator/core/scripts/retro.sh --check-core-report <file> --project <the project root>`
   (Windows `-CheckCoreReport <file> -Project <the project root>`) until it passes: exit 0 and nothing
   printed. It refuses a body that is not the template (a missing, renamed or extra line or section, a
   feature row not in `FEATURES.md`, more than three proposals, a `<fill>` left, an HTML comment `<!--`
   after the first line, a Profile cell outside its vocabulary) and anything that could identify a
   project or a person — a URL or a Markdown link, an e-mail (also written with `[at]` or `(at)`), an
   `@handle`, an IP address, an IPv6 address (a `::` next to a hex group — `fe80::1ff:fe23:4567:890a`,
   `::1` — or 6 or more colon-separated groups of 1–4 hex digits; a time `12:30:45` or a ratio `1:2:3`
   passes), an HTML character reference (`&#<digits>;`, `&#x<hex>;` or `&<letters>;` — GitHub renders
   `&#64;` as `@` and `&period;` as `.`; a lone `&` and `R&D` pass), a path (a drive letter, `/x/y`,
   `x\y`), a dotted name anywhere in a word — a host (`name.com's`, `name.com:8080`) or a file name — that
   is not one of the core's own file names, a commit id (a hex token of 7 or more digits, any case,
   holding a decimal digit; one of decimal digits only is named "a long number or a commit id"), the
   project folder's name as a whole word in any case, a free-text cell over 160 characters; each refusal
   names its line. The line is rewritten, never the rule. Not refused (they rest on the owner's review of
   every body): an address in plain words (`user [ at ] host`, "at … dot"), a full-width `＠` or `。`, an
   IDN host, the project folder's name written with `_` or a space.
4. **Show the owner** the whole body; **the owner's yes files it** — nothing is filed without it. A body
   the owner edits passes the check again before it is filed.
5. **Title** `[retro-report] <id> <from>..<to>`. **One per project-period:** first `gh issue list -R
   Arziburst/claude-coordinator --state all --search "\"<id> <from>..<to>\" in:title"`; one found →
   nothing new is filed.
6. **File** with the owner's own gh login: `gh issue create -R Arziburst/claude-coordinator --title
   "<title>" --body-file <file>`. No label is set here (a label for `[retro-report]` titles is the
   owner's separate decision).
7. **Book-keep:** once filed, the *Settings* row **Last core report** set to the period `<from>..<to>`
   (`owner, <date>`); one journal line — `core retro report <from>..<to>: filed #<n>` (or `shown, not
   filed`) —, a commit in `coordinator/`. A report not filed leaves the row as it was, so the next one
   covers its period again.

**What leaves the machine:** only what the template holds — the numbers above, the core's own names (its
feature ids, the guard's reasons and refusal sources as fixed keys, the roles, the findings' statuses),
the anonymous id, the dates, the core commits, and the short lines the checker passed.

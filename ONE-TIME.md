# One-time steps

Settings and checks that run once: at init, or at the first "update the core" after the core added
them. They work like database migrations: this catalog lists every step the core has ever added, and
each project's `coordinator/CHECKLIST.md` records which of them ran there, so an update asks only what
is new and never asks a recorded answer again (CORE §3, [procedures/UPDATE-CORE.md](procedures/UPDATE-CORE.md)).

## The catalog

| id | added | scope | kind | default | what |
|---|---|---|---|---|---|
| `strictness` | #32 e8f78a1 | project | setting | from the init research; standard when unsure | swarm / standard / strict and the rows the project overrides (CORE §3) → `PROJECT.md` |
| `spend-level` | #21 dba3845 | project | setting | balanced | lean / balanced / thorough (CORE §7) → `PROJECT.md` |
| `coordinator-name` | #60 | project | setting | `<Project> Coordinator` | the coordinator session's name, always containing the English word `Coordinator` (INIT 3.1, question 10) → `PROJECT.md` *Settings*; the owner renames the session with `/rename` |
| `core-reports` | #70 | project | setting | automatically (client work: show me first) | how core findings reach claude-coordinator (INIT 3.1, question 11) → `PROJECT.md` *Settings* |
| `core-findings` | #70 | project | check | run | `coordinator/CORE-FINDINGS.md` exists in the template's format; an older record of core problems is converted to it on the owner's yes ([procedures/CORE-FINDINGS.md](procedures/CORE-FINDINGS.md)) |
| `work-mode` | #73 | project | setting | by task (a team with a board: batch) | how the owner gives work, and housekeeping on events instead of a cycle (INIT 3.1, question 12; CORE §4) → `PROJECT.md` *Settings*; a project that ran cycles keeps its recipe as the batch recipe |
| `self-improvement` | #132 | project | setting | show me first (the first week always; then the owner's choice) | whether the weekly retro sends an anonymous summary of numbers to claude-coordinator — send / show me first / only me (INIT 3.1, question 13; [procedures/RETRO.md](procedures/RETRO.md)) → `PROJECT.md` *Settings*, with the anonymous id from `scripts/retro --new-id` |
| `model-own-limits` | #21 dba3845 | project | setting | none known | which models have their own limit (e.g. Fable) and whether their spend also counts toward the weekly one, read by the owner in `/usage` (CORE §7a) → BINDINGS *Models* |
| `state-branch` | #44 1ebe968 | project | check | run | the state repository is on its one branch `state`, also the remote's default; on `main` / `master` → the move of CORE §12b, on the owner's yes |
| `state-private` | #12 0e9f5f0 | project | check | run | the state repository's remote is `PRIVATE` (`gh repo view --json visibility`), or local only is recorded in `PROJECT.md`; its note records the visibility read (`PRIVATE` / `PUBLIC`) |
| `statusline-verified` | #38 99e1704 | machine | check | run | the status line is installed and its `cost` line for one finished session matches `scripts/session-tokens` at list price (TOOLKIT *Usage*) |
| `safety-hook-test` | #7 c8655e4 | machine | check | run | the hook's self-test prints `safety-guard: OK` and the worker safety file points at it (TOOLKIT *Safety*) |
| `protected-root` | #118 | project | setting | on: the project root | the worker safety file's `env` `COORD_PROTECTED_ROOT` (the project root) and `Edit\|Write\|MultiEdit\|NotebookEdit` in the guard's matcher, so workers' edit tools are kept from the owner's working copy (TOOLKIT *Safety*); `selftest hooks` says SKIP without it |
| `model-probe` | #21 dba3845 | machine | check | run | one probe per model, the ladder written to BINDINGS *Models* (CORE §7) |
| `spend-ratio` | #21 dba3845 | project | check | run | the first limit percent per dollar, from `scripts/session-tokens --since <reset>`, written to BINDINGS *Models* (CORE §7a) |
| `prices-file` | #120 | project | check | run | `coordinator/prices.txt`, the prices file `scripts/run-stats --limits` reads (TOOLKIT *Usage*), exists with one line per ladder model — `<model id> <input> / <output> / <cache read> / <cache write>` in USD per million tokens, from the list prices in BINDINGS *Models* (cache write at the 1-hour price), `not-weekly` after a model the `model-own-limits` answer keeps out of the weekly limit; only a model whose price is unknown is asked from the owner; BINDINGS *Models* names the file (CORE §7a) |
| `branch-protection` | #7 c8655e4 | project | check | run | the main branch on the code host requires a PR and passing checks (and a human review in the strict preset), or why not is recorded (INIT *Safety check*); its note records the repository's visibility (`PUBLIC` / `PRIVATE`) |
| `first-real-pr-watched` | #45 c6982d5 | project | check | run | the first real PR after init is followed end to end — CI, review, merge — and the result reported: what no sandbox can show |
| `selftest` | #48 | machine | check | run | the full self-test passes on this machine at the core commit in use ([procedures/SELFTEST.md](procedures/SELFTEST.md)): in the state repository, its branches and PR kept as evidence; it runs again after every update (UPDATE-CORE step 4), each CHECKLIST line naming the commit; it runs after every update, so a `declined` line is offered again at each update, never run silently |

- **scope** — `project`: once per project; `machine`: once per project on each machine (its
  CHECKLIST row names the machine's `hostname`), so a new machine is asked again.
- **kind** — a `setting` is a question, asked with its default first (INIT 3.1); the answer goes where
  the row says and into CHECKLIST. A `check` is an action, offered as "run now? yes/no".
- **added** — the core PR and its squash commit (`git log --grep '(#45)'` finds a commit not yet listed).
- **Re-run on a change:** `branch-protection` and `state-private` are offered again when the
  repository's visibility differs from the one their CHECKLIST note recorded (`gh repo view --json
  visibility`, read at start): a public repository brings fork PRs and free branch protection.
- A new setting or check adds its row **in the same PR** that adds it. Rows are never removed or
  renumbered: a retired step stays, marked *retired*, and is no longer asked.

## The checklist — `coordinator/CHECKLIST.md`

In the coordinator's own git (CORE §12b), one line per step that ran, newest last:

```
| id | date | core | machine | result | note |
|---|---|---|---|---|---|
| strictness | 2026-10-12 | 1ebe968 | - | done | swarm (owner) |
| safety-hook-test | 2026-10-12 | 1ebe968 | dev-laptop | done | safety-guard: OK |
| branch-protection | 2026-10-12 | 1ebe968 | - | declined | the plan does not offer it |
```

- **core** — the claude-coordinator commit the project ran on; **machine** — `hostname` for a
  machine row, `-` for a project row.
- **result** — `done` · `failed` (offered again at the next update) · `declined` (never asked again
  unless the owner asks) · `n/a` (does not apply, e.g. no code host; the note says why).
- **When it is written:** the init quiz and its setup fill it (INIT 3.5); every "update the core"
  offers the rows missing for this project or this machine (UPDATE-CORE step 3); a new machine offers
  its machine rows (HANDOFF). A step run again later on the owner's word gets a new line; the newest
  line counts.

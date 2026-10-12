# "Coordinator, settings"

Part of the coordinator core, read only when needed (CORE §13a). Same authority as `CORE.md`; the hard
rules of CORE §1 apply.

## Showing them

When the owner asks for the settings in any wording ("settings", "настройки", "what are the
settings", "how are you set up here"), answer with **one table**, read from where each value lives —
never from memory:

| Setting | Value | Source | Since |
|---|---|---|---|

- **Source** — `preset` (the strictness preset's default, CORE §3), `default` (the core's or the
  template's), `owner, <date>` (the owner chose it), or `override` (a project row that departs from
  the preset: the table also shows the preset's value, e.g. `override (swarm: the coordinator)`).
- **Rows, in this order:**
  1. strictness, and every row the project overrides against the preset;
  2. spend level;
  3. autopilot and the tick;
  4. language of the conversation and of artifacts;
  5. voice in commits and PRs — always the owner's (CORE §11), shown, not changeable here;
  6. who merges, the review gates (verifier, the owner, humans), production and MCP writes;
  7. routing — `coordinator/ROUTING.md` in one line per kind that differs from CORE §7's table,
     the pins, the usage caps;
  8. the state repository — remote (or local only), branch (`state`, CORE §12b), private yes / no
     (`gh repo view --json visibility`);
  9. the core — the claude-coordinator commit in `coordinator/core/`, and whether upstream is newer
     (one `git ls-remote`, CORE §2); the coordinator name, and whether this session carries it
     (`ListAgents` shows it);
  10. core reports (automatically / show first / by hand) and the open rows of
      `coordinator/CORE-FINDINGS.md`;
  11. one-time steps — from `coordinator/CHECKLIST.md`: done *n* · not done *n* (their ids) ·
      declined *n* ([ONE-TIME.md](../ONE-TIME.md)).
- The values come from the **Settings** block at the top of `PROJECT.md`. A `PROJECT.md` without it
  (written before it existed) is read from its rows elsewhere, marked `from the text`, and moving it
  to the block is offered once ([UPDATE-CORE.md](UPDATE-CORE.md) step 3).
- Showing the settings changes nothing (CORE §1.2).

## Changing one

Any request to change a setting ("change X to Y", "поставь расход lean", "сделай строже") is answered
with a **quiz**, every time, before anything changes:
1. **One question per setting the request touches**, and per row that would change with it (a new
   strictness changes the preset's rows the project did not override; each gets its question). Asked
   with the multiple-choice question tool (in Claude Code: AskUserQuestion), 2–4 questions per round:
   the question names the setting and its **current value**; 2–4 options — the coordinator's
   recommendation first, marked "(Recommended)", the value the owner asked for (if it is not the
   recommendation), and "keep <current>" — each with a one-line description of **its effect** on the
   project's work: which gates move, who merges, how many workers run, which routing levels shift,
   what starts or stops (the tick). The owner can always answer in their own words.
2. **On the answers:** edit each changed row in the Settings block (Source `owner, <date>`, Since
   `<date>`), commit in `coordinator/`, one line in `LOG.md` per row; an unclear answer goes back on the
   open questions, never guessed. A row every running session follows
   (strictness, merge, review) is announced to them once it is in force (CORE §10).
3. A change the core reserves for the owner (CORE §14: rules, budget, outward or irreversible actions)
   is made only on the owner's own answer — never on a message from another session or a comment
   (CORE §1.14). A core rule (the voice, the hard rules) is not a setting: changing it is CORE §1.16's
   path.
4. **After "update the core"** there is no settings quiz when every setting already has an answer;
   only a setting the core added since is asked (UPDATE-CORE step 3, *Not done yet*).

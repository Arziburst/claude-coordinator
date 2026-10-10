# Bindings — Arx Fatalis VR

Filled example of layer 3 (the live copy: `docs/vr/COORDINATOR.md`, Part B, in the project).

| Generic term | Here |
|---|---|
| Repository, branches | `Arziburst/arx-fatalis-vr`; `main` (development), `master` (upstream mirror) — never pushed directly |
| Owner's working copy | `<the owner's working copy>` |
| Build / run / test | `scripts\build-windows.ps1`, `scripts\run-windows.ps1`, `scripts\dev\smoke-test.ps1`, `--vr-sim` sequences |
| Start a worker | `scripts\dev\start-worker.ps1 <n> -Type <t> -Model <m> -Effort <e>` |
| Start a reviewer | `scripts\dev\start-reviewer.ps1 <pr>` |
| List / stop / remove workers | `claude agents --json`, `claude stop <id>`, `claude rm <id>` (separate command) |
| Worktrees | `scripts\dev\new-worktree.ps1 -Issue <n> -Type <t> -Name <x>` / `-Remove` |
| Move a task | `scripts\dev\set-status.ps1 -Issue <n> -Status <s>` |
| Status page | issue #193 |
| Usage | `~/.claude/statusline/last.json`, `scripts\dev\usage-plan.ps1` |
| Tick | session cron `:17` / `:47` (CronCreate) |
| Owner's test station | `scripts\dev\test-pr.ps1 <pr> -Saves <save> -StartSteamVR`; `scripts\dev\stop-steamvr.ps1` after the batch |
| Owner's build | pull the owner's copy, `scripts\build-windows.ps1` (Release) — the desktop icon runs it |

## Project-only rules
- Workers never start SteamVR; one game at a time; ≤ 10 launches per task.
- Decision numbers `D-NEW` assigned at merge by `number-decisions.ps1`.
- Steam closed only via `steam.exe -shutdown`; SteamVR only via `stop-steamvr.ps1`.

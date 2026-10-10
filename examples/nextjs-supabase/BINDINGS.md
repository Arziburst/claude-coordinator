# Bindings — example: a client web app (Next.js + Supabase)

| Generic term | Here |
|---|---|
| Repository, branches | `<org>/<app>`; `main` deploys production — never pushed directly |
| Build / run / test | `npm run dev`, `npm run lint`, `npm run typecheck`, `npm run build`, `npm run test:unit` |
| Definition-of-done checks | lint + typecheck + build + unit tests; with a migration also `npm run db:reset` + `npm run test:db` (pgTAP) |
| Start a worker | a background Claude session in its worktree: `git worktree add .claude/worktrees/<issue>-<slug> -b <issue>-<slug> origin/main` |
| Per-task resources | worktree `.claude/worktrees/<issue>-<slug>` · Supabase stack `app-<issue>` (`supabase start --workdir …` with a per-task `config.toml` project id) · ports `54000 + (<issue> mod 100) * 10` |
| Start / stop a task's environment | `npm run db:start` / `npm run db:stop` in the worktree |
| Shared resources | `app-main` stack (mirror of `main`), guarded by a pre-script that refuses a reset from a worktree |
| Move a task | `gh project item-edit --field-id <Status id> --single-select-option-id <option id>` |
| Preview | Vercel preview URL on the PR (SSO; automation bypass secret for smoke tests) |
| Production migrations | GitHub Actions workflow `db-migrate-prod` (manual, `confirm=apply`) |
| Claude permission rules | `.claude/settings.json` deny-list: `git push --force*`, `git push origin main`, `supabase db push*`, `vercel --prod*`, production `execute_sql` / `apply_migration` |

## Traps
- Docs can disagree about which database backs which environment — confirm before any migration.
- A smoke workflow without its bypass secret passes as "skipped" — read the job, not the badge.

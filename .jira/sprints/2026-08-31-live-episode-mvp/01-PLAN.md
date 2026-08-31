---
sprint: 2026-08-31-live-episode-mvp
plan: I
wave: I
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false # waves serialize merges and within-wave file claims are disjoint; a single checkout is safe (sprint-wide rationale — other plans reference this line)
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: []
parallel_with: [II]
files_modified:
  - server/config/dev.exs
  - server/config/test.exs
  - server/config/runtime.exs
  - flake.nix
  - .env.example
  - README.md
covers:
  - D-09
  - D-16
  - "RESEARCH: port-mismatch pitfall (Vite→57400 vs Phoenix 4000; Repo→5432 vs flake 57432)"
  - "GOAL: bootable stack every other plan depends on"
effects:
  - DEV-01
  - DEV-02
  - DEV-03
  - DEV-04
---

# Plan I: DevX wiring — ports, env, run docs

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** Track 5. A stack that boots on first try: Phoenix on 57400 (what Vite proxies to), Postgres on 57432 (what the flake runs), FAL_KEY sourced from a gitignored .env, and written run instructions.

All work happens inside `nix develop` (elixir/node/ffmpeg/postgres provided; `pg-start` boots Postgres on 57432).

## Tasks

### I. Pin the three ports

- **Files:** `server/config/dev.exs`, `server/config/test.exs`, `server/config/runtime.exs`
- **Read first:** `server/config/dev.exs`, `server/config/test.exs`, `server/config/runtime.exs` (note: runtime.exs sets `http: [port: System.get_env("PORT", "4000")]` for ALL envs and executes after dev.exs — it overrides any dev.exs pin unless its default changes too)
- **Action:** Per D-09: (1) in `dev.exs` add `port: 57432` to the `Whn.Repo` config block and change the endpoint line to `http: [ip: {127, 0, 0, 1}, port: 57400]`; (2) in `test.exs` add `port: 57432` to the `Whn.Repo` config block; (3) in `runtime.exs` change `System.get_env("PORT", "4000")` to `System.get_env("PORT", "57400")`. Touch nothing else in these files.
- **Done when:** With `pg-start` running: `(cd server && mix ecto.create)` exits 0 (DEV-01); `(cd server && mix phx.server)` boot output contains `127.0.0.1:57400` (DEV-02, kill after verifying); `grep -c 57432 server/config/dev.exs server/config/test.exs` shows 1 each.
- **Covers:** D-09, RESEARCH port pitfall

### II. Flake shellHook — PORT export and .env sourcing

- **Files:** `flake.nix`, `.env.example`
- **Read first:** `flake.nix` (shellHook lines 39–49), `.gitignore` (`.env` is already ignored — verify, don't edit)
- **Action:** Per D-09/D-16, append to the shellHook after the PG exports:

  ```
  export PORT=57400
  if [ -f "$PWD/.env" ]; then
    set -a; . "$PWD/.env"; set +a
  fi
  ```

  Create `.env.example` at the repo root containing exactly two lines: a comment `# copy to .env (gitignored); loaded by the nix devshell` and `FAL_KEY=`.
- **Done when:** `grep 'PORT=57400' flake.nix` and `grep '\.env' flake.nix` match; `.env.example` exists with a `FAL_KEY=` line; `git check-ignore .env` exits 0 (DEV-03); a fresh `nix develop --command sh -c 'echo $PORT'` prints 57400.
- **Covers:** D-09, D-16

### III. Development section in README

- **Files:** `README.md`
- **Read first:** `README.md` (product brief — append, don't restructure), `flake.nix` (command names)
- **Action:** Append a `## Development` section after §15 with the exact sequence: `nix develop` → `pg-start` → `cp .env.example .env` and fill `FAL_KEY` → `(cd server && mix setup)` → `(cd server && mix phx.server)` (API on 127.0.0.1:57400) → `(cd web && npm install && npm run dev)` (UI on the Vite port, proxying `/socket` and `/api` to 57400) → `pg-stop` when done. Note Postgres runs on 57432 and that `mix test` needs `pg-start` running. Keep it under ~25 lines; write for an external reader.
- **Done when:** `grep -E 'pg-start|mix setup|mix phx.server|npm run dev' README.md` matches all four (DEV-04).
- **Covers:** D-16, GOAL (onboarding to the bootable stack)

## Nyquist criteria for this plan

- [ ] `mix ecto.create` exits 0 against Postgres 57432 (DEV-01)
- [ ] Phoenix boot log shows 127.0.0.1:57400 (DEV-02)
- [ ] `.env` gitignored, shellHook sources it, `.env.example` committed (DEV-03)
- [ ] README Development section names all four run commands (DEV-04)

## Risks accepted in this plan

- Prod deploys still control PORT/DATABASE_URL via env; the 57400 runtime default is a dev convenience and is overridable — accepted.
- `initdb --auth=trust` makes the `postgres` password inert locally; fine for a dev-only database.
- No CI wiring this sprint; verification is local-shell only.

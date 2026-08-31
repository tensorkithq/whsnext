---
sprint: 2026-08-31-live-episode-mvp
plan: V
wave: II
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: [I]
parallel_with: [III, IV]
files_modified:
  - server/priv/repo/migrations/*_create_core_tables.exs
  - server/lib/whn/schemas/episode.ex
  - server/lib/whn/schemas/beat.ex
  - server/lib/whn/schemas/decision.ex
  - server/lib/whn/schemas/vote.ex
  - server/lib/whn/store.ex
  - server/test/whn/store_test.exs
covers:
  - D-01
  - "GOAL: Postgres persistence for episodes/beats/decisions/votes (BRIEF track 2)"
  - "RESEARCH: unique index (decision_id, anon_id) as durable backstop; jsonb via :map fields; AGENTS.md Ecto rules (programmatic fields never cast, mix ecto.gen.migration)"
effects:
  - DB-01
  - DB-02
  - DB-03
---

# Plan V: Persistence — migrations, schemas, Store context

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** Track 2. The durable layer: four tables per the BRIEF (episodes, beats, decisions, votes), Ecto schemas, and a synchronous `Whn.Store` context. No EpisodeServer wiring here — that composes in Plan VII against the pinned Store interface.

`server/AGENTS.md` Ecto rules are binding: migrations via `mix ecto.gen.migration`, `:string` even for text columns, programmatic fields (`anon_id`, all `*_id` FKs) set explicitly, never in `cast`. Runs inside `nix develop` with `pg-start` on 57432 (Plan I merged).

## Tasks

### I. Core tables migration [BLOCKING schema push]

- **Files:** `server/priv/repo/migrations/<timestamp>_create_core_tables.exs`
- **Read first:** CONTEXT.md D-01 + "Pinned interfaces" (Store), `server/AGENTS.md` Ecto guidelines, `README.md` §11 (persistence scope; this sprint persists the BRIEF's four tables, not the full §11 list)
- **Action:** Generate with `mix ecto.gen.migration create_core_tables`. Tables: `episodes` (`title :string`, `premise :text` via `:string` schema type, `seed :integer`, `phase :string`, `story_state :map`, timestamps); `beats` (`episode_id references(:episodes)`, `idx :integer`, `kind :string` — "scene"|"bridge", `script :string`, `video_prompt :string`, `segments {:array, :string}`, `meta :map`, timestamps, unique index `(episode_id, idx, kind)`); `decisions` (`episode_id references(:episodes)`, `beat_idx :integer`, `question :string`, `options {:array, :string}`, `tallies {:array, :integer}`, `winner_idx :integer`, `deadline_ms :bigint`, timestamps); `votes` (`decision_id references(:decisions)`, `anon_id :string`, `option_idx :integer`, timestamps, **unique index `(decision_id, anon_id)`** per D-01). Then run the push: `mix ecto.migrate` — this is BLOCKING; without it every "tests pass" claim downstream is a false positive.
- **Done when:** `(cd server && mix ecto.migrate)` exits 0 and `psql -p 57432 -U postgres -d whn_dev -c '\dt'` lists episodes, beats, decisions, votes (DB-01); `grep 'unique_index(:votes' server/priv/repo/migrations/*_create_core_tables.exs` matches.
- **Covers:** D-01 (durable backstop), GOAL persistence

### II. Schemas + Whn.Store context with tests

- **Files:** `server/lib/whn/schemas/{episode,beat,decision,vote}.ex`, `server/lib/whn/store.ex`, `server/test/whn/store_test.exs`
- **Read first:** the migration from task I, CONTEXT.md "Pinned interfaces" (Store function names — conform exactly), `server/test/support/data_case.ex`, `server/AGENTS.md` Ecto rules
- **Action:** One schema module per table under `Whn.Schemas.*` mirroring the migration (`story_state`/`meta` as `:map`, arrays as `{:array, _}`). `Whn.Store` — synchronous functions only (async wrapping happens in Plan VII, not here): `create_episode(attrs) :: {:ok, %Episode{}}`; `upsert_beat(episode_id, %{idx, kind, script, video_prompt, segments, meta})` upserting on `(episode_id, idx, kind)` with `on_conflict: {:replace, [:segments, :meta, :script, :video_prompt]}`; `record_decision(episode_id, %{beat_idx, question, options, tallies, winner_idx, deadline_ms}) :: {:ok, %Decision{}}`; `record_vote(decision_id, anon_id, option_idx)` with `on_conflict: :nothing` per D-01, `decision_id`/`anon_id` set explicitly on the struct (never cast); `update_story_state(episode_id, map)`. Tests via `Whn.DataCase`: DB-02 (call `record_vote` twice for the same `(decision_id, anon_id)` with different idx; assert exactly one row and the original `option_idx`), DB-03 (create episode → upsert beat with two segment URLs → record decision with `winner_idx` → `update_story_state`; read back and assert field equality).
- **Done when:** `(cd server && mix test test/whn/store_test.exs)` exits 0 (DB-02, DB-03); `grep 'on_conflict: :nothing' server/lib/whn/store.ex` matches.
- **Covers:** D-01, RESEARCH Ecto idioms

## Nyquist criteria for this plan

- [ ] `mix ecto.migrate` exits 0; four tables exist (DB-01)
- [ ] Duplicate `(decision_id, anon_id)` cannot produce a second row (DB-02)
- [ ] Episode/beat/decision/story-state round-trip (DB-03)

## Risks accepted in this plan

- README §11's fuller table list (plots, analytics, anon-user table, generation metadata as first-class rows) is deliberately reduced to the BRIEF's four tables + `meta`/`story_state` maps — the BRIEF supersedes §11 for MVP scope.
- Backend-restart timeline reconstruction is out of scope (persist yes, recovery flow deferred — CONTEXT Deferred ideas).
- Store is synchronous by design; the hot-path fire-and-forget wrapping is Plan VII's responsibility and is tested there.

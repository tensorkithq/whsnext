---
sprint: 2026-08-31-live-episode-mvp
plan: VII
wave: IV
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false # rationale in Plan I — waves serialize merges, file claims are disjoint
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: [III, IV, V, VI]
parallel_with: []
files_modified:
  - server/lib/whn/episode_server.ex
  - server/lib/whn/episodes.ex
  - server/lib/whn/store.ex
  - server/lib/whn/seed.ex
  - server/priv/repo/seeds.exs
  - server/test/whn/integration_test.exs
  - README.md
covers:
  - D-13
  - "D-01/D-15 wiring (fire-and-forget vote rows; error handling composed end to end)"
  - "RESEARCH: Ecto fire-and-forget via named Task.Supervisor; beat-tagged pipeline results composed with persistence"
  - "GOAL: the full loop closes — video → vote → canonical decision → generated continuation"
effects:
  - E2E-01
  - E2E-02
  - E2E-03
---

# Plan VII: Integration — wire pipeline + store into the EpisodeServer, seed Lagos Wahala, close the loop

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** The composition wave: EpisodeServer persists its truth through `Whn.Store`, drives the real `Whn.Pipeline`, boots from the Lagos Wahala seed, and the whole merged tree passes its gates. (Cross-track by nature; for issue-cutting, tasks I–II attach to tracks 1/2/3 and task III to the sprint gate.)

All prior waves are merged: `Whn.Fal`/`Whn.Frames` (III), EpisodeServer/channel (IV), Store/migrations (V), Celeris/Pipeline (VI). This plan runs solo in wave IV, so extending `store.ex` conflicts with nothing.

## Tasks

### I. Persistence + pipeline wiring in the EpisodeServer

- **Files:** `server/lib/whn/episode_server.ex`, `server/lib/whn/episodes.ex`, `server/lib/whn/store.ex`
- **Read first:** `server/lib/whn/episode_server.ex` (current state; re-read before editing), `server/lib/whn/store.ex` (pinned Store API), `server/lib/whn/pipeline.ex` (message contract), CONTEXT.md "Claude's discretion" (per-vote fire-and-forget)
- **Action:** Add `Whn.Store.finalize_decision(decision_id, tallies, winner_idx) :: {:ok, %Decision{}}` to `server/lib/whn/store.ex` (a plain update of those two fields; the five pinned Store functions are untouched). `Whn.Episodes.start!(attrs)` now calls `Whn.Store.create_episode/1` first and passes the DB id into the server (episode row is the durable identity). In the EpisodeServer: on `vote_open` → `Store.record_decision` (synchronous — boundary write) and keep `current_decision_id` in state; on each accepted vote → `Task.Supervisor.start_child(Whn.TaskSupervisor, fn -> Whn.Store.record_vote(decision_id, anon_id, idx) end)` (fire-and-forget; unique index makes replays safe per D-01); on lock → `Store.finalize_decision(current_decision_id, tallies, winner_idx)` (synchronous — boundary write); on `{:celeris, r}` → `Store.update_story_state(episode_id, merged_state)`; on bridge/segment completion → `Store.upsert_beat` with kind/segments/meta (include fal request metadata in `meta`). The default `pipeline_impl` (`Whn.Pipeline`) is now real: `ctx` built from state per the pinned shape (`beat`, `seed`, `episode`, `story_state`, `winning_choice` = options[winner_idx], `last_frame_url`, `history`); the opening path (Plan IV's trigger) gets the same treatment with `winning_choice`/`last_frame_url` nil. Keep every Store call off the tick hot path except the two boundary writes (decision open/finalize).
- **Done when:** `(cd server && mix test)` exits 0 — all wave II/III suites still green with wiring in place; `grep 'finalize_decision' server/lib/whn/store.ex server/lib/whn/episode_server.ex` matches both; `grep 'Task.Supervisor.start_child' server/lib/whn/episode_server.ex` matches the vote write.
- **Covers:** D-01/D-15 wiring, RESEARCH fire-and-forget idiom

### II. Lagos Wahala seed — "Salary Just Entered"

- **Files:** `server/lib/whn/seed.ex`, `server/priv/repo/seeds.exs`, `README.md`
- **Read first:** `PLOT.md` §3–4 (premise, tone), §15 (continuity rules), `server/priv/repo/seeds.exs`, CONTEXT.md D-13
- **Action:** `Whn.Seed.salary_just_entered/0` returns the start attrs per D-13: `title: "Lagos Wahala — Salary Just Entered"`, premise (2–3 sentences from PLOT.md §4: salary lands; landlord wants money, mother wants attention, friend has a business proposal, commute looms, relationship complications), `seed:` a fixed integer, and an initial `story_state` map (protagonist name + archetype, `money_ngn`, `relationships` (landlord/mother/friend/partner with a standing note each), `active_problems` list, `location`, `time_of_day`, `current_objective`). `priv/repo/seeds.exs` inserts the episode row via `Whn.Store.create_episode(Whn.Seed.salary_just_entered())` (idempotent: skip if a row with the same title exists). Append a short "Start the live episode" snippet to README's Development section: `iex -S mix phx.server` then `Whn.Episodes.start!(Whn.Seed.salary_just_entered())` — with the FAL_KEY + cost warning (each cycle ≈ $2.00 post-promo).
- **Done when:** `(cd server && mix run priv/repo/seeds.exs)` exits 0 twice in a row (idempotent); `grep 'Salary Just Entered' server/lib/whn/seed.ex README.md` matches both.
- **Covers:** D-13, GOAL seed content

### III. End-to-end integration test + final gates [BLOCKING]

- **Files:** `server/test/whn/integration_test.exs`
- **Read first:** `server/test/whn/episode_server_test.exs` and `server/test/support/{pipeline_stub,fal_mock}.ex` (drive the cycle the same way), `features/integration.feature`
- **Action:** One DataCase+ChannelCase-style test file, sandboxed DB, `pipeline_impl` = PipelineStub (or `Whn.Pipeline` with `fal_impl` = FalMock — prefer the latter: it exercises the real pipeline): E2E-01 — `Whn.Episodes.start!(Whn.Seed.salary_just_entered())` creates an episodes row (query by title) and a Registry-registered server that broadcasts `phase`; E2E-02 — join a channel client, drive `{:timeline, :vote_open}`, push two votes from distinct anon_ids, drive `{:timeline, :vote_lock}`, let pipeline messages flow, then assert: a decisions row with the locked `winner_idx` and final tallies, votes rows for both anon_ids, and a beats row whose `segments` holds the mock URLs (poll the sandbox briefly for the async vote writes using repeated queries, not `Process.sleep` — e.g. drain via `:sys.get_state` on the server then assert). Final BLOCKING gates run in order and must all exit 0: `(cd server && mix ecto.migrate)` (schema push re-verified on the merged tree), `(cd server && mix precommit)` (compile --warnings-as-errors, format, full test suite), `(cd web && npm run build)`.
- **Done when:** All three gate commands exit 0 (E2E-03) and `mix test test/whn/integration_test.exs` exits 0 covering E2E-01/E2E-02.
- **Covers:** GOAL full loop, E2E gates

## Nyquist criteria for this plan

- [ ] Seed episode boots: row + registered server + phase broadcast (E2E-01)
- [ ] Driven cycle persists decisions/votes/beats with the locked winner (E2E-02)
- [ ] `mix ecto.migrate`, `mix precommit`, `npm run build` all exit 0 on the merged tree (E2E-03)

## Risks accepted in this plan

- No live-fal end-to-end run in tests (cost + nondeterminism); the Plan III spike is the live-call evidence, and the mocked pipeline exercises identical code paths. A manual live run via the README snippet is the operator's smoke test.
- Backend-restart recovery remains deferred: rows exist to reconstruct a timeline, but no code reads them back on boot.
- Fire-and-forget vote writes can lose a row on a crash between reply and insert; the GenServer tally remains the runtime authority for the decision outcome.
- Multi-viewer playback-sync tolerance (README §14.10) is unmeasured; client seek math is deterministic but real-device drift is future work.

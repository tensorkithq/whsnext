---
sprint: 2026-08-31-live-episode-mvp
verified_at: 2026-08-31T20:08:01Z
verdict: PASS
---

# Verification: 2026-08-31-live-episode-mvp

Goal-backward audit of the executed sprint. Asks: "does the codebase, as it stands now, deliver what the goal promised?" — distinct from `jira-nyquist` (which asks "do tests cover the criteria?") and `jira-reviewer` (which audits the diff).

## Goal

One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.

## Goal decomposition

- [x] 1. A vertical scene plays (server playback broadcasts + web dual-player stage)
- [x] 2. The audience votes in a server-synced 10s window (open +10s, lock +20s, live tallies, immutable votes)
- [x] 3. The locked winner — and only the winner — generates the bridge and next scene via fal
- [x] 4. Episode truth persists in Postgres (episodes / beats / decisions / votes)
- [x] 5. Proof surface: passing server test suites
- [x] 6. Proof surface: timed fal spike log
- [x] 7. Proof surface: migrated Postgres tables
- [x] 8. Proof surface: production build of the web client

## Findings

### 1. A vertical scene plays

- **Status:** delivered
- **Evidence:** `source-audit` — server: `server/lib/whn/episode_server.ex:262-275` (`advance/1` broadcasts `playback {kind, beat, segments, started_at_ms}` and schedules the scene boundary at `segments × 10s`); client: `web/src/components/stage.tsx:8-17` (segment + offset derived from `Date.now() + skewMs - started_at_ms` across 10s segments), `stage.tsx:144-165` (both `<video>` muted + playsInline behind a tap gate, hold shimmer at 159-160), standby warm with `#t=0.001` at `stage.tsx:21,81`. Wire conformance: every broadcast the client subscribes to in `web/src/lib/useEpisode.ts:42-66` (`phase`, `playback`, `preload`, `vote_open`, `vote_update`, `vote_locked`, `vote_closed`) has a matching server emit in `episode_server.ex` with matching payload keys; join reply carries the five `EpisodeSync` keys (`episode_server.ex:76-86` vs `web/src/lib/types.ts:26-32`). Frozen protocol lib byte-identical: `command` — `git diff 2578348..HEAD --stat -- web/src/lib/` is empty.
- **Evidence:** `command` — a live Phoenix server is up on the pinned port: websocket upgrade probe `curl -i "http://127.0.0.1:57400/socket/websocket?vsn=2.0.0&anon_id=verifier-probe"` → `HTTP/1.1 101 Switching Protocols`.

### 2. Server-synced 10s vote window

- **Status:** delivered
- **Evidence:** `source-audit` — `episode_server.ex:21-26` (`vote_open_ms: 10_000`, `vote_window_ms: 10_000`), `episode_server.ex:272` (`:vote_open` scheduled at scene start +10s, scene playback only), `episode_server.ex:149` (`deadline_ms = now_ms() + vote_window_ms` — absolute epoch ms), `episode_server.ex:157` (lock scheduled 10s after open → +20s from scene start), `episode_server.ex:91-101` (first write wins via `Map.put_new`; accepted vote → immediate `vote_update {tallies}`; duplicate replies ok with the original pick), `episode_server.ex:283-290` (post-lock → `{:error, :locked}`), channel translation `server/lib/whn_web/channels/episode_channel.ex:42-48` (`{reason: "locked"}` on the wire). Client countdown from `deadline_ms - (Date.now() + skewMs)` at `web/src/components/vote-overlay.tsx:81,92` with rAF, width-transition bars (`web/src/styles.css:237`).
- **Evidence:** `command` — tests asserting the timeline, tie-break, immutability, and lock rejection all pass in the live run: `mix test` → **37 tests, 0 failures** (`server/test/whn/episode_server_test.exs:42,72,84,114`; `server/test/whn_web/channels/episode_channel_test.exs:46,55,63,75,87,92`).

### 3. Locked winner generates the bridge and next scene via fal

- **Status:** delivered
- **Evidence:** `source-audit` — at lock the winner is picked (max tally, lowest index on ties — `episode_server.ex:166-167`) and exactly one cycle is dispatched with `winning_choice = options[winner_idx]` (`episode_server.ex:180-188`); zero viewers park the ctx (`pending_cycle`) until a presence recheck (D-12, `episode_server.ex:130-137`). `server/lib/whn/pipeline.ex:37-52` runs the winner-only cycle: Celeris script → bridge clip → `Whn.Frames.last_frame` → three chained i2v segments (`pipeline.ex:102-115`), each stage retried once with the identical closure/seed (`pipeline.ex:147-158`), reporting `{:pipeline, beat, ...}` messages in the pinned order. Celeris is the real API per REVISED D-05 (`server/lib/whn/celeris.ex:16,55,73-88`: bearer `CELERIS_KEY`, `celeris-1`, temp 0.6, max_tokens 700, `seed + beat`, strict `json_schema`), with brace-slice + clamp + canned fallback (`celeris.ex:124-211`). fal endpoints per pinned contract (`server/lib/whn/fal/fal_ex_impl.ex:23-26`); frame extraction is the exact D-06 recipe (`server/lib/whn/frames.ex:37-50`: Req download → `ffmpeg -y -sseof -0.25 ... -frames:v 1 -q:v 3` → `Whn.Fal.upload`).
- **Evidence:** `command` — pipeline order/params/retry and Celeris parse/fallback tests pass in the live 37/37 run (`server/test/whn/pipeline_test.exs:92,113,138,163`; `server/test/whn/celeris_test.exs:70-166`). `artifact` — the live fal legs were proven by the timed spike (outcome 6) and EXECUTION.md records a live Celeris smoke through the shipped code path (claim, corroborated by the spike log for fal legs).
- **Observation (not a gap against a locked decision):** `state.last_frame_url` is initialized nil and never reassigned (`episode_server.ex:63,388` — no other write; confirmed by `grep -rn last_frame_url server/lib`), so every production cycle takes the t2v bridge branch (`pipeline.ex:86-96`); the i2v-bridge branch (`pipeline.ex:98-100`, tested at `pipeline_test.exs:93,114`) is unreachable in live operation, and `pipeline.ex:127` deliberately skips extracting the final segment's frame. Within-scene frame chaining is real; cross-beat visual continuity is prompt-only. Plan VI explicitly specified the nil→t2v fallback and no plan task assigns the field, so this is delivered-as-planned — flagged under Next steps as a quality follow-up.

### 4. Episode truth persists in Postgres

- **Status:** delivered
- **Evidence:** `source-audit` — `server/lib/whn/store.ex:13-61` (pinned five functions + `finalize_decision/3`; `record_vote` inserts with `on_conflict: :nothing` onto the unique `(decision_id, anon_id)` index); wiring in `episode_server.ex:304-377` (synchronous boundary writes for decision open/finalize, fire-and-forget `Task.Supervisor` writes for votes, story state, and beats); `server/lib/whn/episodes.ex:11-19` (episode row created first, DB id is the registry identity); seed content per D-13 in `server/lib/whn/seed.ex:16-25` with an idempotent guard in `server/priv/repo/seeds.exs:12`.
- **Evidence:** `command` — end-to-end drive passes in the live run: `server/test/whn/integration_test.exs:90-173` boots the real seed through `Episodes.start!`, runs the full mocked loop over the real `Whn.Pipeline` + real ffmpeg frame path, and asserts the decision row (winner_idx 1, tallies [0,2,0]), both vote rows, the bridge beat, and the 3-segment scene beat with `meta["seed"] = seed + beat`.

### 5. Passing server test suites

- **Status:** delivered
- **Evidence:** `command` — re-run live in the nix devshell: `cd server && mix test` → `37 tests, 0 failures` (seed 815036).

### 6. Timed fal spike log

- **Status:** delivered
- **Evidence:** `artifact` — `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log`: `STAGE flux 12130ms`, `STAGE i2v 4940ms`, `STAGE last_frame 2946ms`, `STAGE t2v 5293ms`, `STAGE vision 1876ms`, `TOTAL 27189ms`, `BUDGET CHECK i2v 4940ms vs 20000ms — within budget`, with hosted fal URLs per stage. Untracked by design (`.jira/.gitignore` ignores `*.log`); script committed at `server/scripts/fal_spike.exs`.

### 7. Migrated Postgres tables

- **Status:** delivered
- **Evidence:** `command` — re-run live: `mix ecto.migrate` → "Migrations already up"; `psql -p 57432 -d whn_dev -c '\dt'` lists `episodes`, `beats`, `decisions`, `votes`; `\d votes` shows `votes_decision_id_anon_id_index UNIQUE (decision_id, anon_id)` (D-01 durable backstop) and the FK to `decisions`.

### 8. Production build of the web client

- **Status:** delivered
- **Evidence:** `command` — re-run live: `cd web && npm run build` → vite build + `[prerender] Prerendered 1 pages` exit 0; `npm run typecheck` (`tsc --noEmit`) exit 0. `source-audit` — `web/vite.config.ts:10` `tanstackStart({ spa: { enabled: true } })`, `:13-15` `/socket` (ws) + `/api` proxy to 127.0.0.1:57400; `web/package.json:15` phoenix `1.8.13`, `:21` `@types/phoenix ^1.6.7`.

### Unverifiable here

- A fully live episode with real fal + Celeris spend (real clips on screen, real votes from phones). Proof would be `command`/`browser` (boot `Whn.Episodes.start!(Whn.Seed.salary_just_entered())` with live keys and watch the client) — spend not sanctioned for verification. Each live leg is individually proven: fal legs by the spike log (artifact), Celeris by the executor's recorded smoke (claim in EXECUTION.md), the loop mechanics by the integration test.

## Source coverage

| Decision | Plan | Implemented | Evidence |
|----------|------|-------------|----------|
| D-00 (goal) | all | yes | this report; outcomes 1-8 |
| D-01 (immutable vote) | 04/05-PLAN | yes | source-audit: `episode_server.ex:91-101,284`; `store.ex:51-54`; unique index in `psql \d votes`; `episode_channel.ex:45` |
| D-02 (tie → lowest index) | 04-PLAN | yes | source-audit: `episode_server.ex:166-167` (`Enum.max_by` keeps the first maximum in index order); command: `episode_server_test.exs:42` |
| D-03 (immediate vote_update) | 04-PLAN | yes | source-audit: `episode_server.ex:95-98` |
| D-04 (topic `episode:live`) | 04-PLAN | yes | source-audit: `episode_channel.ex:14-28` (resolves via `Whn.Episodes.current/0`; other subtopics rejected); command: `episode_channel_test.exs:87` |
| D-05 REVISED (real Celeris API) | 06-PLAN | yes | source-audit: `celeris.ex:16,55,73-88` (endpoint, bearer key, celeris-1, 0.6/700, seed, strict json_schema); fallback `vision/2` retained `fal.ex:20-21,34`, `fal_ex_impl.ex:26` |
| D-06 (local ffmpeg frames) | 03-PLAN | yes | source-audit: `frames.ex:37-50` (exact recipe); used on the pipeline path `pipeline.ex:130-132`; command: `frames_test.exs` green in 37/37 |
| D-07 (hold phase) | 02/04-PLAN | yes | source-audit: server `episode_server.ex:277-279,235-238`; client `stage.tsx:88-160` (freeze + shimmer); command: `episode_server_test.exs:95` |
| D-08 (phoenix 1.8.13 npm) | 02-PLAN | yes | source-audit: `web/package.json:15,21` |
| D-09 (ports 57432/57400) | 01-PLAN | yes | source-audit: `dev.exs:8,23`, `test.exs:12`, `runtime.exs:23` (PORT default "57400"), `flake.nix:50`; command: ws probe on 57400 → 101, psql on 57432 |
| D-10 (web re-bootstrap, frozen libs) | 02-PLAN | yes | source-audit: `vite.config.ts:10,13-15`; command: `git diff 2578348..HEAD -- web/src/lib/` empty |
| D-11 (fal_ex behind Whn.Fal) | 03-PLAN | yes | source-audit: `fal.ex:14-39` (5 callbacks, `:fal_impl` dispatch); `mix.exs` carries fal_ex + req; command: `fal_test.exs` (dispatch of all five ops) in 37/37 |
| D-12 (zero-viewer cost guard) | 04-PLAN | yes | source-audit: `episode_server.ex:119-141,182-188`; command: `episode_server_test.exs:129,146` |
| D-13 (Lagos Wahala seed) | 07-PLAN | yes | source-audit: `seed.ex:16-25` (title, Tunde, money_ngn 250_000, seed 20_260_831), `seeds.exs:12` idempotent guard; command: `integration_test.exs:93-95` in 37/37 |
| D-14 (timing model) | 04/06-PLAN | yes | source-audit: `episode_server.ex:21-26,149,157,272`; bridge clamp 8..12 `celeris.ex:168`, next_scene forced 30 `celeris.ex:148` |
| D-15 (retry once, vote never reopens) | 06-PLAN | yes | source-audit: `pipeline.ex:145-158`; `celeris.ex:31-42,189-211`; `next_choices` consumed at vote_open `episode_server.ex:158`, error path never touches `vote` `episode_server.ex:235-238`; command: `pipeline_test.exs:163`, `celeris_test.exs:121` |
| D-16 (secrets in .env) | 01-PLAN | yes | command: `git check-ignore .env` → ignored; `git ls-files .env.example` → tracked; source-audit: `flake.nix:51-52` (`set -a; . .env`) |

Pinned interfaces conform: wire protocol (outcome 1), `Whn.Fal` callbacks (`fal.ex:14-22` byte-match the contract), `Whn.Frames.last_frame/1`, pipeline boundary + message shapes (`pipeline.ex:17-18,140-143`), `Whn.Episodes.current/0` + `join_sync/2` + `vote/3` (`episodes.ex:22-27`, `episode_server.ex:35-38`), supervision names (`application.ex:15-18`), Store functions (`store.ex`).

## Predicate coverage

All 33 sprint predicates are claimed and sensed; the server suite (37 tests) passed in a live re-run during this verification.

| @req | Claimed by plan | Sensed | Evidence |
|------|-----------------|--------|----------|
| DEV-01 | 01-PLAN | yes | command: `mix ecto.migrate` exit 0 against 57432 (re-run); DB reachable via psql -p 57432 |
| DEV-02 | 01-PLAN | yes | command: live server on 127.0.0.1:57400 answered a ws upgrade with 101; boot attempt log names port 57400 ("already in use" by the running instance) |
| DEV-03 | 01-PLAN | yes | command: `git check-ignore .env` ok; source-audit: `flake.nix:50-52`; `.env.example` tracked |
| DEV-04 | 01-PLAN | yes | source-audit: `README.md:445-450` (nix develop, pg-start, mix setup, mix phx.server, npm run dev) |
| WEB-01 | 02-PLAN | yes | command: `npm run build` + `npm run typecheck` exit 0 (re-run); source-audit: `vite.config.ts:10`, `package.json:15` |
| WEB-02 | 02-PLAN | yes | source-audit: `stage.tsx:144-165` (muted + playsInline ×2, tap gate) |
| WEB-03 | 02-PLAN | yes | source-audit: `stage.tsx:21,76-86` (`#t=0.001`, muted play-then-pause warm) |
| WEB-04 | 02-PLAN | yes | source-audit: `vote-overlay.tsx:49,81,92` (width-% bars, `deadlineMs - (now + skewMs)`, rAF); `styles.css:237` |
| WEB-05 | 02-PLAN | yes | source-audit: `stage.tsx:8-17,62` (segment/offset from `started_at_ms` + skew across 10s segments) |
| FAL-01 | 03-PLAN | yes | command: 37/37 incl. `fal_test.exs` (five-op dispatch); source-audit: `fal.ex:14-39` |
| FAL-02 | 03-PLAN | yes | command: `frames_test.exs` green in 37/37; source-audit: `frames.ex:46` (`-sseof -0.25`) |
| FAL-03 | 03-PLAN | yes | artifact: `fal-spike.log` — 5 STAGE lines, TOTAL 27189ms, BUDGET CHECK within budget |
| EP-01 | 04-PLAN | yes | command: `episode_channel_test.exs:46` in 37/37 |
| EP-02 | 04-PLAN | yes | command: `episode_channel_test.exs:55` in 37/37 |
| EP-03 | 04-PLAN | yes | command: `episode_channel_test.exs:63` + `episode_server_test.exs:72` in 37/37 |
| EP-04 | 04-PLAN | yes | command: `episode_channel_test.exs:75` in 37/37 |
| EP-05 | 04-PLAN | yes | command: `episode_server_test.exs:42` in 37/37 (race fixed in b4d0a1e) |
| EP-06 | 04-PLAN | yes | command: `episode_server_test.exs:95` in 37/37 |
| EP-07 | 04-PLAN | yes | command: `episode_server_test.exs:114` in 37/37 |
| EP-08 | 04-PLAN | yes | command: `episode_server_test.exs:129` in 37/37 |
| EP-09 | 04-PLAN | yes | command: `episode_server_test.exs:146` in 37/37 |
| DB-01 | 05-PLAN | yes | command: migrate exit 0; psql `\dt` lists all four tables (re-run) |
| DB-02 | 05-PLAN | yes | command: `store_test.exs:39` in 37/37; unique index confirmed in psql |
| DB-03 | 05-PLAN | yes | command: `store_test.exs:50` in 37/37 |
| CEL-01 | 06-PLAN | yes | command: `celeris_test.exs:70` in 37/37 |
| CEL-02 | 06-PLAN | yes | command: `celeris_test.exs:114,121,140` in 37/37 |
| CEL-03 | 06-PLAN | yes | command: `celeris_test.exs:148,158` in 37/37 |
| CEL-04 | 06-PLAN | yes | command: `pipeline_test.exs:92` in 37/37 |
| CEL-05 | 06-PLAN | yes | command: `pipeline_test.exs:113,138` in 37/37 |
| CEL-06 | 06-PLAN | yes | command: `pipeline_test.exs:163` in 37/37 |
| E2E-01 | 07-PLAN | yes | command: `integration_test.exs:90` in 37/37 |
| E2E-02 | 07-PLAN | yes | command: `integration_test.exs:105` in 37/37 |
| E2E-03 | 07-PLAN | yes | command: migrate + `mix test` + `npm run build` all re-run live, exit 0 |

## Verdict

**PASS** — all 8 decomposed outcomes delivered; all 17 locked decisions implemented with evidence; 33/33 predicates claimed and sensed. The commit gate that blocked Plan VI mid-sprint was resolved (its two commits landed as `c96e1a3` and `6ef6ab2`); no commit command is pending.

## Next steps

None required for the verdict. Quality follow-ups for a future sprint:

1. **Cross-beat frame chaining never engages in production.** `EpisodeServer.state.last_frame_url` is set nil at init and never updated (`server/lib/whn/episode_server.ex:63,388`), and `Whn.Pipeline` skips extracting the final segment's frame (`server/lib/whn/pipeline.ex:127`), so every live bridge takes the t2v branch and the tested i2v-bridge branch (`pipeline.ex:98-100`) is unreachable outside tests. Capture the last scene frame at cycle end and thread it into the next ctx if pixel continuity across beats is wanted (README §2 "bridge must naturally connect" is currently narrative-only).
2. **Winner reveal is invisible on the client.** `vote_locked` and `vote_closed` broadcast back-to-back (`episode_server.ex:169-170`); `useEpisode.ts:66` nulls the vote on `vote_closed`, so the locked-winner poll styling (`vote-overlay.tsx:43`) never renders in the live flow. Delay `vote_closed` a beat (or drop it until the bridge plays) to show the result.
3. **Artifacts on disk only:** `fal-spike.log` (ignored by `.jira/.gitignore`) and `EXECUTION.md` (untracked) live only in the working tree — orchestrator bookkeeping, not code.

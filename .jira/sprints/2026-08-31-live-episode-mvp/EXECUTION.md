# Execution: 2026-08-31-live-episode-mvp

Append-only log of what happened during `/jira:execute`. The executor writes here; humans read it.

## Started

2026-08-31T18:47:01Z

## Branch / worktree

jira/2026-08-31-live-episode-mvp (single checkout, no worktree — waves serialize merges, within-wave file claims are disjoint)

## Plan I

Note: working tree had a pre-existing modification to `.jira/STATE.md` (orchestrator bookkeeping, outside this plan's files) at start; Plan II runs in parallel in this same checkout per the sprint's `worktree: false` rationale. Proceeded.

### Plan I task I: Pin the three ports
- **Commit:** `ddb9bac`
- **Result:** done
- **Notes:** dev.exs Repo +`port: 57432`, endpoint `http: [ip: {127,0,0,1}, port: 57400]`; test.exs Repo +`port: 57432`; runtime.exs PORT fallback `"4000"`→`"57400"`. Verified: `mix ecto.create` exit 0 against pg-start's 57432 (DEV-01; needed `mix local.hex --force && mix local.rebar --force && mix deps.get` first — fresh repo-local MIX_HOME); phx.server boot log `Running WhnWeb.Endpoint with Bandit 1.12.5 at 127.0.0.1:57400 (http)` (DEV-02); `grep -c 57432` = 1 in each config. Path-scoped commit (`git commit -- <paths>`) to avoid index races with Plan II.

### Plan I task II: Flake shellHook — PORT export and .env sourcing
- **Commit:** `ae348dd`
- **Result:** done
- **Notes:** Appended `export PORT=57400` + `.env` sourcing (`set -a; . "$PWD/.env"; set +a`) after the PG exports; created `.env.example` (comment + `FAL_KEY=`). Verified: both greps match; `git check-ignore .env` exits 0 (DEV-03, `.gitignore` line 4 pre-existing — not edited); fresh `nix develop --command sh -c 'echo $PORT'` prints 57400.

### Plan I task III: Development section in README
- **Commit:** `60b0101`
- **Result:** done
- **Notes:** Appended `## Development` after §15 (21 lines): nix develop → pg-start → cp .env.example → mix setup → mix phx.server (127.0.0.1:57400) → npm run dev (Vite proxies /socket + /api to 57400) → pg-stop; notes 57432 pinning and `mix test` needing pg-start. All four command greps match (DEV-04).

### Plan I Nyquist results
- [x] `mix ecto.create` exits 0 against Postgres 57432 (DEV-01) — verified live, task I
- [x] Phoenix boot log shows 127.0.0.1:57400 (DEV-02) — verified live, task I
- [x] `.env` gitignored, shellHook sources it, `.env.example` committed (DEV-03) — verified, task II
- [x] README Development section names all four run commands (DEV-04) — verified, task III

Elixir config compiled cleanly during the ecto.create/phx.server boots; no linter is configured for nix or markdown in this repo.

**Plan I finished:** 2026-08-31T19:12Z. Commits: ddb9bac, ae348dd, 60b0101.

## Plan II

Started 2026-08-31T18:52Z. Same checkout as Plan I (`worktree: false`); pre-existing `.jira/STATE.md` dirt is orchestrator bookkeeping outside this plan's files — proceeding, commits stage `web/` paths only. Frozen files snapshotted for byte-identity check: `src/lib/{types,identity,useEpisode}.ts`.

### Plan II task I: Re-bootstrap web/ as TanStack Start (SPA mode)
- **Commit:** `3af3c63`
- **Result:** done
- **Notes:** Scaffolded with `npx @tanstack/cli create --blank --no-git --no-toolchain --non-interactive` (a trust gate blocks recursive force-delete prefixes; the scaffold itself ran fine in repo tmp/). Transplanted: vite.config with `tanstackStart({spa:{enabled:true}})`, `/socket` (ws) + `/api` proxy, `host: true`; phoenix pinned `1.8.13`, `@types/phoenix ^1.6.7`. `web/index.html` deleted — TanStack Start owns the shell; title "Lagos Wahala — Live" + viewport meta (`maximum-scale=1, viewport-fit=cover`) moved to `__root.tsx` head() (the plan's "scaffold equivalents" clause). Frozen lib hashes verified identical pre/post (types 6be533…, identity ef7ba7…, useEpisode 2bac36…). Build, typecheck, and all done-when greps pass. Stack landed: vite 8.2.2, TS 6, react-start 1.168.x; esbuild postinstall was not blocked, no approve-scripts step needed.

### Plan II task II: Vertical dual-player stage
- **Commit:** `12c2f1f`
- **Result:** done
- **Notes:** Small deviation: `web/src/routes/index.tsx` (a task-I file) edited to mount `<Stage/>` — the plan's task-I text anticipates this ("root route renders the episode page"). Seek math uses a `#t=` media-fragment src (native seek-on-load; doubles as the iOS first-frame paint trick) rather than a post-loadedmetadata `currentTime` write — same server-clock derivation (`Date.now() + skewMs - started_at_ms`, floor/clamp per WEB-05). Done-when: build 0, typecheck 0, playsInline x2, muted x2, literal `#t=0.001` present, started_at_ms in locate(), hold/shimmer in tsx+css.

### Plan II task III: Instagram-poll vote overlay + countdown + HUD
- **Commit:** `445c347`
- **Result:** done
- **Notes:** Small deviation (same shape as task II): `index.tsx` edited to mount `<Hud/>` and the vote-gated `<VoteOverlay/>`. Countdown is its own component keyed by `deadline_ms` so the rAF re-render stays local to the timer; bar total derives from remaining-at-mount (no client-hardcoded window length). No eslint is configured in web/ — verification is `tsc --noEmit` + `vite build`. Done-when: build 0, typecheck 0, backdrop-filter behind @supports with solid rgba fallback, `transition: width 300ms ease` on `.poll-fill`, deadline math `deadline_ms - (now + skewMs)` in vote-overlay.tsx.

### Plan II aggregate
- Final tree: `npm run typecheck` and `npm run build` (SPA prerender) exit 0.
- Frozen protocol lib: `git diff 2578348..HEAD -- web/src/lib/` is empty — byte-identical.
- Scope: plan commits (`3af3c63`, `12c2f1f`, `445c347`) touch only `web/`.
- Nyquist self-check: WEB-01 spa.enabled + phoenix 1.8.13 ✓; WEB-02 muted+playsInline x2 behind tap gate ✓; WEB-03 standby `#t=0.001` + muted play/pause warm ✓; WEB-04 rAF countdown on `deadline_ms` + `skewMs`, width-transition bars ✓; WEB-05 seek derived from `started_at_ms` across 10s segments ✓.
- Scaffold temp dir removed.

Plan II finished 2026-08-31T19:14Z.

## Plan V

Started 2026-08-31T19:02Z. Same checkout (`worktree: false`); pre-existing `.jira/STATE.md` dirt is orchestrator bookkeeping and Plans III/IV run in parallel here — proceeding with path-scoped commits (server/priv/repo/migrations, server/lib/whn/schemas, server/lib/whn/store.ex, server/test/whn/store_test.exs).

## Plan IV

Started 2026-08-31T19:20Z. Same checkout (`worktree: false`), parallel with Plans III and V; pre-existing `.jira/STATE.md` dirt is orchestrator bookkeeping, and Plan III's uncommitted `server/mix.exs`/`mix.lock` are outside this plan's files — proceeding with path-scoped commits per Plan I precedent. Baseline compile initially failed on Plan III's mid-flight deps.get (fal_ex/req not yet fetched); retried once per the cross-plan race rule and it passed.

### Plan IV task I: Realtime skeleton — supervision, socket, presence
- **Commit:** `efc981d`
- **Result:** done
- **Notes:** application.ex children inserted after PubSub / before Endpoint in pinned order (Presence, EpisodeRegistry, EpisodeSupervisor, TaskSupervisor); UserSocket rejects missing/empty anon_id, id = "anon:<anon_id>"; endpoint mounts /socket (websocket only) above the LiveView comment. `mix compile --warnings-as-errors` 0; both done-when greps match.

### Plan V task I: Core tables migration [BLOCKING schema push]
- **Commit:** `47c3adf`
- **Result:** done
- **Notes:** Generated via `mix ecto.gen.migration create_core_tables`. Push ran: `mix ecto.migrate` exit 0 (log: created episodes, beats, decisions, votes + beats_episode_id_idx_kind_index + votes_decision_id_anon_id_index). psql `\dt` on whn_dev lists all four tables (DB-01); `grep 'unique_index(:votes'` matches. Small deviation: beats `script`/`video_prompt` columns are `:text` (plan said `:string`) — generated scripts exceed varchar(255); mirrors the plan's own `premise :text` idiom, schema fields stay `:string` per AGENTS.md.

## Plan III

Started 2026-08-31T19:00Z. Same shared checkout (`worktree: false`); commits are path-scoped to this plan's files. Pre-existing `.jira/STATE.md` dirt is orchestrator bookkeeping — untouched.

### Plan III task I: Deps + Whn.Fal wrapper
- **Commit:** `5f42d80`
- **Result:** done
- **Notes:** fal_ex 0.1.0 + req 0.5 added; `mix deps.get` run (this plan holds the mix.exs/mix.lock claim). `Whn.Fal` has the 5 pinned callbacks + same-name public functions dispatching via `Application.get_env(:whn, :fal_impl, Whn.Fal.FalExImpl)`. Adapter finding: fal_ex calls `Tesla.client(middleware)` with no adapter (Tesla would fall back to `:httpc`) while shipping hackney — pinned `config :tesla, adapter: Tesla.Adapter.Hackney` in `config/config.exs` (small deviation: file not in files_modified; unclaimed by any plan; documented in FalExImpl moduledoc). Naming note: CONTEXT "Pinned interfaces" parenthetical says default impl `Whn.Fal.FalEx`, plan body + file list say `Whn.Fal.FalExImpl` — followed the plan; the cross-plan contract (`:fal_impl` app env + callbacks) is unchanged. Upload goes through `FalEx.storage() |> FalEx.Storage.upload(path)` (upload/2 is on the storage struct, not module-global). Done-when: compile --warnings-as-errors 0; @callback count = 5; fal_impl grep matches; fal_ex in mix.exs; "req" in mix.lock.

### Plan III task II: Whn.Frames — local last-frame extraction
- **Commit:** `802b659`
- **Result:** done
- **Notes:** Red-green: test written first (2 failures, UndefinedFunctionError), then frames.ex. `last_frame/1` takes http(s) URLs or local paths (plan's testability widening); Req streams the download to tmp (`into: File.stream!`), exact D-06 ffmpeg recipe, upload via `Whn.Fal` dispatch (test stubs `:fal_impl` with an inline `@behaviour Whn.Fal` module, env restored in on_exit), both tmp files rm'd in `after`. Done-when: `mix test test/whn/frames_test.exs` → 2 tests 0 failures (FAL-02); sseof grep matches line 46; compile --warnings-as-errors clean.

### Plan V task II: Schemas + Whn.Store context with tests
- **Commit:** `17fdd46`
- **Result:** done
- **Notes:** TDD (tdd skill): red-green per slice — vote-immutability test failed on undefined Whn.Store, then passed; round-trip test failed on undefined upsert_beat/update_story_state, then passed. Four Whn.Schemas.* modules (belongs_to for FKs, story_state/meta :map, arrays); Store conforms to the pinned names exactly, upsert_beat uses `on_conflict: {:replace, [:segments, :meta, :script, :video_prompt]}` + `conflict_target: [:episode_id, :idx, :kind]`, record_vote sets decision_id/anon_id/option_idx on the struct (no cast) with `on_conflict: :nothing` per D-01. Added one test beyond the plan's two: upsert-replace on an existing (episode, idx, kind) — exercises the pinned conflict_target, which DB-03 alone never hits. `mix test test/whn/store_test.exs` 3 tests 0 failures (DB-02, DB-03); `grep 'on_conflict: :nothing'` matches; `mix format --check-formatted` + `mix compile --warnings-as-errors` clean on plan files.

### Plan V Nyquist results
- [x] `mix ecto.migrate` exits 0; episodes/beats/decisions/votes in whn_dev `\dt` (DB-01) — verified live, task I
- [x] Duplicate `(decision_id, anon_id)` yields exactly one row with the original option_idx (DB-02) — store_test
- [x] Episode → beat (2 segment URLs) → decision (winner_idx) → story_state round-trip (DB-03) — store_test

No eslint/tsc applies to server/; verification is mix compile --warnings-as-errors + mix format --check-formatted + ExUnit. Full `mix precommit` deferred to wave close — it would compile Plans III/IV mid-flight state in this shared checkout.

**Plan V finished:** 2026-08-31T19:07Z. Commits: 47c3adf, 17fdd46.

### Plan III task III: Timed fal spike
- **Commit:** `ffe74ae` (script only)
- **Result:** deviated — spike RUN pending on FAL_KEY
- **Notes:** `server/scripts/fal_spike.exs` committed: 5 `:timer.tc`-wrapped stages (flux 720x1280 → i2v 10s/480P/disabled/seed 42 from the HOSTED flux url → Whn.Frames.last_frame round-trip → t2v 10s/480P/9:16/balanced/seed 42 → vision gemini-2.5-flash-lite with the frame in image_urls, one-sentence JSON ask), `STAGE <name> <ms>ms` lines, `TOTAL`, `BUDGET CHECK` of i2v ms vs 20_000ms. Repo-root `.env` does not exist and `$FAL_KEY` was absent in a fresh `nix develop` shell (re-checked twice, 45s apart, after spawn-time absence). Per orchestrator instruction the ≈$1 run was NOT attempted; the FAL_KEY-unset abort path was verified live (clear stderr message, exit 1 — zero spend). `fal-spike.log` not created; FAL-03 unmet. To finish once FAL_KEY lands in `.env`: `(cd server && mix run scripts/fal_spike.exs) 2>&1 | tee ../.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log` — run once, don't loop.

### Plan III aggregate
- Nyquist self-check: FAL-01 compile clean w/ 5-callback wrapper + `:fal_impl` dispatch ✓; FAL-02 frames test green on local ffmpeg recipe ✓; FAL-03 spike log — PENDING (FAL_KEY absent; script committed and abort-path verified).
- Scope: commits `5f42d80`, `802b659`, `ffe74ae` touch only this plan's files plus one logged line in `server/config/config.exs` (Tesla adapter pin, unclaimed file).
- Toolchain checks: `mix compile --warnings-as-errors` exit 0; `mix format --check-formatted` on this plan's lib/test files clean; no Elixir linter (credo) configured in this repo.
- Risk note for the eventual run: fal_ex's queue status/result URLs (`queue.fal.run/<id>/status/<req>`) differ from fal's documented `/requests/<req>/status` shape, and its production submit posts to `fal.run/<id>` with `Prefer: respond-async`. If the header is ignored the call degrades to a long sync request and `FalEx.subscribe/2` still returns the output (300s Tesla timeout covers it); if polling 404s, the accepted-risk fallback (Req over the documented queue URLs, confined to `fal_ex_impl.ex`) applies.

**Plan III finished (tasks I–II complete, task III run pending):** 2026-08-31T19:32Z. Commits: 5f42d80, 802b659, ffe74ae.

### Plan IV task II: Whn.EpisodeServer + Whn.Episodes — the state machine
- **Commit:** `d5232d4`
- **Result:** done
- **Notes:** TDD red-green (8 failures module-undefined → 8/8 pass). Pinned state keys kept verbatim; minimal internals added: `next_choices` (consumed at vote_open so a vote can never reopen for the same beat, D-15), `durations` (stored per plan, scheduling still uses segment_ms per D-14), `opening_started` (exactly-once opening), `pending_cycle` (D-12 lock-with-zero-viewers parks the ctx until a presence recheck), `viewer_count_fn` (test injection, defaults to Presence list size). Planner-unspecified choices: VoteState.question is a constant "What happens next?" (celeris §5 result has no question field); out-of-range option_idx replies `{:error, :no_open_vote}` instead of crashing the episode; `{:error, stage, reason}` holds only when nothing is playing (mid-playback errors let the scene finish, the boundary then holds); bridge_ready queues without a preload broadcast (plan-literal — preload is specified under segment_ready only). Lock bumps state.beat, so straggler segments of the prior beat are dropped by the stale guard — accepted MVP edge. Tests cover EP-05/06/07/08/09 + D-01 duplicate-vote immutability + join_sync shape; `mix compile --warnings-as-errors` 0; both done-when greps match.

### Plan IV task III: EpisodeChannel — thin translator over the frozen protocol
- **Commit:** `079defd`
- **Result:** done
- **Notes:** TDD red-green (5 failures → 6/6 pass). Tests cover EP-01 (five EpisodeSync keys), EP-02 (presence_state keyed by anon_id), EP-03 (duplicate push replies original pick, tallies unchanged), EP-04 (post-lock vote → "locked"), plus D-04 subtopic rejection and UserSocket anon_id gating. `handle_in("vote", ...)` guards `is_integer(option_idx)` — a malformed frame crashes only that client's channel process (Phoenix-normal isolation), never the episode. ChannelCase follows the Phoenix 1.8 generated shape (`import Phoenix.ChannelTest` + `@endpoint`; the plan's `use Phoenix.ChannelTest, endpoint:` form takes no such option in 1.8) with sandbox setup delegated to `Whn.DataCase.setup_sandbox/1`. Done-when: channel test file exits 0; `grep 'episode:live'` matches; compile warning-clean.

### Plan IV aggregate
- Both suites together: 14 tests, 0 failures; `mix compile --warnings-as-errors` and `mix format --check-formatted` clean on all plan files.
- Wire conformance: event names and payload keys taken byte-exact from `web/src/lib/types.ts` + `useEpisode.ts` (phase/playback/preload/vote_open/vote_update/vote_locked/vote_closed; EpisodeSync five keys; vote reply {tallies, your_vote} / {reason: "locked"}).
- Nyquist self-check: EP-01..EP-09 all asserted (see task notes); D-01/02/03/04/07-server/12/14 implemented as specified.
- Scope: plan commits (`efc981d`, `d5232d4`, `079defd`) touch only this plan's declared files; all adds path-scoped (shared checkout with Plans III/V).
- No linter beyond compiler warnings + formatter is configured for Elixir in this repo.

**Plan IV finished:** 2026-08-31T19:58Z. Commits: efc981d, d5232d4, 079defd.

### Plan III task III (continued): spike RUN — FAL_KEY landed
- **Commits:** `ffa2c00` (fixes surfaced by the live run)
- **Result:** done
- **Notes:** FAL_KEY appeared in `.env`; fresh `nix develop` sourced it. Run 1: flux died at 5.7s with `{:error, :timeout}` — hackney's default 5s `recv_timeout` (fal_ex's Tesla layer allows 300s but the adapter read timed out). Fix: adapter pin now `{Tesla.Adapter.Hackney, recv_timeout: 300_000}` in config/config.exs. Run 2: flux 12.0s + i2v 5.5s succeeded (hosted-URL image_url validated), then `last_frame` failed `{:error, :nxdomain}` — fal_ex's `FalEx.Storage` derives its upload host by string-replace to `v3.fal-cdn.com`, which has no DNS record (clip download from v3b.fal.media was fine, confirmed via getent/curl). Applied the plan's accepted fallback confined to `fal_ex_impl.ex`: `upload/1` now uses Req against fal's current storage REST flow (`rest.alpha.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3` → presigned PUT), verified with a free jpg upload smoke test before re-running; frames test still green, compile/format clean. Run 3 (complete): STAGE flux 12130ms / i2v 4940ms / last_frame 2946ms / t2v 5293ms / vision 1876ms, TOTAL 27189ms, BUDGET CHECK i2v 4940ms vs 20000ms — within budget. Validates D-05 (image-attached vision returned clean one-sentence JSON), D-06 (full extract round-trip ~3s), D-16, and the README §2 timing model (10s/480P clips ≈ 5s, ~4x headroom; flux opening frame 12.1s is pre-episode, off the vote path). Spend: 1 partial (flux), 1 partial (flux+i2v), 1 full run — ≈ $1.60 total at promo pricing. `fal-spike.log` grep: 5 STAGE lines + TOTAL + BUDGET CHECK (FAL-03). Deviation note: the log is NOT committed — the committed `.jira/.gitignore` line 7 ignores `*.log` by design (plan files_modified conflicts with repo policy; did not force-add). Artifact lives on disk at `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log` alongside the rest of the untracked sprint workspace.

### Plan III aggregate (final)
- FAL-01 ✓ (5f42d80), FAL-02 ✓ (802b659), FAL-03 ✓ (log on disk, run 3).
- Commits: 5f42d80, 802b659, ffe74ae, ffa2c00.

**Plan III finished:** 2026-08-31T20:14Z.

## Plan VI

Started 2026-08-31T20:30Z. Solo this wave (waves I–II merged). Same checkout (`worktree: false`); tree clean apart from this untracked sprint log. Executing the REVISED plan: Whn.Celeris calls the real Celeris chat-completions API (Bearer CELERIS_KEY, strict json_schema per REVISED D-05) — not Whn.Fal.vision. Timeouts derived from fal-spike.log measured × 3 (flux 12130, i2v 4940, last_frame 2946, t2v 5293 ms).

### Plan VI task I: Prompts + Whn.Celeris — the script engine
- **Commit:** BLOCKED — trust gate refused `git commit` (requires L4, executor at L3); files staged-ready, command below
- **Result:** done (code + tests), blocked (commit)
- **Notes:** TDD red-green (8 failures module-undefined → 8/8 pass). `Whn.Prompts`: system prompt pins the §5 contract after "Return ONLY compact JSON, no markdown fences, exactly this shape:", FINAL FRAME HYGIENE + wordless-sound clause, PLOT §5 choice rules, §6 bridge vocabulary, §15 continuity; `vertical_suffix/0` = "Vertical 9:16 smartphone cinematic, handheld, natural Lagos light."; `user_prompt/1` renders premise/state/history and "OPENING — establish the premise and first decision" when winning_choice is nil. `Whn.Celeris.run/1` POSTs via Req to the D-05 endpoint (config `:whn, :celeris` — `url`, `key_env` default "CELERIS_KEY" fetched at call time, `req_options` for the Req.Test plug), body exactly per plan (model celeris-1, temp 0.6, max_tokens 700, seed+beat, response_format json_schema strict "beat" with the §5 JSON Schema); brace-slice (`~r/\{.*\}/s`) + Jason + per-field clamp (bridge 8..12, next_scene forced 30 per D-14, choices sliced/padded to 3, missing script/video_prompt invalidates); retry once then canned D-15 fallback (never raises, scene_summary empty so no false story truth); suffix appended to both video_prompts on the way out. Small deviation: the fallback's "reuse prior choices" is unimplementable — ctx carries no prior options (pinned ctx: beat/seed/episode/story_state/winning_choice/last_frame_url/history) — so it uses three canned direction-agnostic choices instead. Done-when: celeris_test 8/8 green (CEL-01/02/03 + request-shape + invalid-field tests); both greps match; format + compile --warnings-as-errors clean.

### Plan VI task II: Whn.Pipeline — winner-only cycle orchestration
- **Commit:** BLOCKED — same trust gate; command below
- **Result:** done (code + tests), blocked (commit)
- **Notes:** TDD red-green (4 failures module-undefined → 4/4 pass). `Whn.Pipeline` defines + implements the pinned behaviour via `Task.Supervisor.start_child(Whn.TaskSupervisor, ...)`; cycle = celeris → bridge (i2v 10s/480P/disabled/seed+beat off last_frame_url, else t2v 9:16/balanced) → `Whn.Frames.last_frame` → 3 chained segments ("Continuation, part n of 3." suffix), messages exactly per pinned contract; opening = celeris (bridge forced nil in the sent result) → flux 720x1280 seed=ctx.seed → chained segments, no bridge message. `with_retry/3`: per-stage Task.async + yield with spike-derived timeouts (flux 36_500, i2v/t2v 16_000, frame 9_000 = measured × 3), one retry with the identical closure (same seed, D-15), second failure → `{:error, stage, reason}` and stop; pipeline task traps exits so a crashing stage becomes an error message, not a silent death. Skips frame extraction after segment 2 (seeds nothing). `Whn.FalMock` (test/support): implements the `Whn.Fal` behaviour, Agent-logged `{fun, args}`, video calls return a real lavfi mp4 fixture so `Whn.Frames` runs its real ffmpeg path against the mock's `upload`, `fail_once/1` for CEL-06. Tests: CEL-04 strict message order; CEL-05 i2v contract + seed=101 + opening flux 720x1280; CEL-06 fail-once → 4 i2v calls, first two byte-identical, no error message. Done-when: pipeline_test 4/4 green; `grep 'seed + '` matches (x2); format + compile clean.

### Plan VI aggregate
- Full suite: `mix test` 33 tests, 0 failures. `mix precommit` (deferred by earlier plans to wave close) exits 0 — compile --warnings-as-errors, deps.unlock --unused (no lock changes), format, tests all clean. No credo/dialyzer configured for Elixir in this repo.
- Live smoke (authorized single call): `Whn.Celeris.run/1` against the real API with the Lagos opening ctx → SMOKE OK. Strict json_schema shaped the reply (all six §5 keys, exactly 3 choices), clamp forced next_scene.duration 30, both video_prompts ended with the vertical suffix, story_state_updates came back as a real object. REVISED D-05 verified end to end through the shipped code path. Spend: ~fractions of a cent.
- Nyquist self-check: CEL-01 ✓, CEL-02 ✓ (fenced parse + double-garbage fallback, no raise, exactly 2 HTTP calls), CEL-03 ✓, CEL-04 ✓, CEL-05 ✓, CEL-06 ✓.
- Scope: only the six declared plan files created; no other file touched (mix.lock, config untouched — Req and Jason were already deps).

### BLOCKER: commits gated
The environment's trust gate refused `git commit` mid-plan ("requires L4, you are L3 — do not retry or route around"). Per the gate's instruction no retry was attempted. Both tasks are code-complete, verified, and path-disjoint; to land them as the plan's two atomic commits, run from the repo root:

```sh
git add server/lib/whn/prompts.ex server/lib/whn/celeris.ex server/test/whn/celeris_test.exs
git commit -m "feat(server): celeris script engine with strict schema and clamped parsing" \
  -m "Whn.Celeris runs one chat-completions call per story beat against the
Celeris API (bearer auth, per-beat seed) and pins the beat contract with
a strict json_schema response format. Replies are still treated as
untrusted: parsing brace-slices the first JSON object out of the text,
truncates every string, clamps the bridge duration to 8-12s, forces the
scene to 30s, and normalizes the choice list to exactly three entries.
An invalid or failed reply is retried once and then replaced by a canned
neutral result, so a generation hiccup can never crash the episode or
reopen a vote.

Whn.Prompts carries the system prompt (JSON contract, final-frame
hygiene so every clip ends on a readable stable frame, wordless-sound
rule, choice-quality and continuity rules, bridge vocabulary) and the
vertical style suffix appended to every outgoing video prompt. Tests
stub the HTTP layer with Req.Test — no live calls." \
  -m "Refs: 2026-08-31-live-episode-mvp plan VI task I"

git add server/lib/whn/pipeline.ex server/test/support/fal_mock.ex server/test/whn/pipeline_test.exs
git commit -m "feat(server): winner-only generation pipeline with idempotent retries" \
  -m "Whn.Pipeline runs one supervised task per beat: Celeris script, bridge
clip out of the vote (image-to-video off the previous scene's last
frame, or text-to-video when none exists yet), last-frame extraction,
then three chained 10s segments that each seed the next via their final
frame. The opening replaces the bridge with a 720x1280 FLUX still built
from the premise. Every stage reports to the episode process as a
beat-tagged message, and each generation call gets one retry with
identical arguments — the fixed seed keeps it idempotent — before the
cycle stops with a stage-tagged error. Stage timeouts are 3x the
wall-clock measured in the fal timing spike.

Tests run against a scripted fal mock that records every call and can
fail once on demand, so the retry path, the parameter contract
(480P/10s/disabled expansion/seed = episode seed + beat), and the
pinned message order are all asserted with zero fal spend." \
  -m "Refs: 2026-08-31-live-episode-mvp plan VI task II"
```

**Plan VI finished (code + verification; commits pending trust):** 2026-08-31T21:05Z.

## Plan VII

Started 2026-08-31T21:40Z. Solo (wave IV), same checkout (`worktree: false`); tree clean except this untracked sprint log. Plan VI's gated commits landed (`c96e1a3`, `6ef6ab2`) — baseline `mix test` 33/33 green before any change. Trust gate did NOT refuse `git commit` for this executor.

### Plan VII task I: Persistence + pipeline wiring in the EpisodeServer
- **Commit:** `734d976`
- **Result:** done
- **Notes:** `Store.finalize_decision/3` added (plain `Ecto.Changeset.change` update of tallies + winner_idx; pinned five functions untouched). `Episodes.start!/1` creates the row first and passes the DB id as both `:id` (registry identity) and `:episode_id` (planner-unspecified detail: persistence guards on `state.episode_id`, nil for direct starts — required so the wave II/III suites, which start the server without a DB row or sandbox, stay green per this task's Done-when). Boundary writes synchronous: `record_decision` at vote_open (decision id kept as `current_decision_id`), `finalize_decision` at lock. Fire-and-forget via `Task.Supervisor.start_child(Whn.TaskSupervisor, ...)`: per-accepted-vote `record_vote` (D-01 index makes replays safe), `update_story_state` on `{:celeris, r}` with the merged map, `upsert_beat` on bridge_ready (`["url"]`) and each segment_ready (accumulated `scene_urls`, reset at lock; meta carries the per-beat fal seed `state.seed + beat`). Default `pipeline_impl` was already `Whn.Pipeline` with the pinned ctx shape (Plan IV/VI) — no change needed there. Accepted micro-risk (noted): concurrent upsert tasks for the same scene beat could land out of order (last-write-wins segments); writes are seconds apart in practice. Done-when: `mix test` 33/33; both `finalize_decision` greps match; `Task.Supervisor.start_child` grep matches (x3) in episode_server.ex.

### Plan VII task II: Lagos Wahala seed — "Salary Just Entered"
- **Commit:** `0705d09`
- **Result:** done
- **Notes:** D-13 content per PLOT §3–4: title "Lagos Wahala — Salary Just Entered", 3-sentence premise (salary lands; landlord/mother/friend/commute/partner pressures), fixed seed 20_260_831, story_state with protagonist (Tunde, "overstretched optimist"), money_ngn 250_000, four relationships with standing notes, 3 active_problems, location/time_of_day/current_objective (string keys — DB round-trip stable). seeds.exs: `import Ecto.Query` + `Repo.exists?` title guard + `Store.create_episode`. README gained "Start the live episode" under Development: `iex -S mix phx.server` + `Whn.Episodes.start!(Whn.Seed.salary_just_entered())`, ≈$2.00/cycle cost warning; also names CELERIS_KEY (REVISED D-05 — the plan text predates the revision but the key is required for a real run). Done-when verified live: `mix run priv/repo/seeds.exs` exit 0 twice, second run skipped the insert (1 row in whn_dev); 'Salary Just Entered' greps match in both files.

### Plan VII task III: End-to-end integration test + final gates [BLOCKING]
- **Commit:** `6205b5b`
- **Result:** done
- **Notes:** Took the plan's preferred path: `pipeline_impl` stays the real `Whn.Pipeline`, fal stubbed with `Whn.FalMock` (lavfi mp4 fixture → real ffmpeg last-frame path), Celeris stubbed via Req.Test — in **shared mode** (`Req.Test.set_req_test_to_shared/0`, restored to private on exit), because the pipeline task is spawned by the EpisodeServer and sits outside the test's `$callers` chain (private-mode stubs would raise there). FalMock started via `start_link` + ordered on_exit (not `start_supervised!`) so it outlives episode teardown. E2E-01: `Episodes.start!(Seed.salary_just_entered())` → episodes row (title/seed/protagonist asserted), `Episodes.current()` == pid, `phase "opening"` broadcast. E2E-02: full mocked loop — opening runs to completion (3 preload broadcasts as the sync point), two channel clients vote option 1, lock → decision row with winner_idx 1 + tallies [0,2,0] + question/options, both vote rows (awaited via repeated queries per the plan — no Process.sleep anywhere), bridge beat idx 1 `[fixture]`, scene beat idx 1 with 3 fixture segments and `meta["seed"]` = seed+beat. Teardown: monitor+DOWN on episode terminate, task-supervisor drain (monitor per child), `current() == nil` await — keeps async writes inside the sandbox window. Flake check: file run 3x green (seeds 801638 + 2 more). Gates (E2E-03), all exit 0 in order: `mix ecto.migrate` ("Migrations already up"), `mix precommit` (35 tests, 0 failures, compile --warnings-as-errors + format clean), `npm run build` (vite build + SPA prerender OK).

### Plan VII Nyquist self-check
- [x] Seed episode boots: row + registered server + phase broadcast (E2E-01) — integration_test
- [x] Driven cycle persists decisions/votes/beats with the locked winner (E2E-02) — integration_test
- [x] `mix ecto.migrate`, `mix precommit`, `npm run build` all exit 0 on the merged tree (E2E-03) — verified live

Toolchain checks: Elixir has no linter beyond compiler warnings + formatter in this repo — both ran clean inside `mix precommit`; web/ was untouched by this plan and its gate (`npm run build`, which runs tsc via vite/prerender pipeline) exits 0. Scope: plan commits (`734d976`, `0705d09`, `6205b5b`) touch only the seven declared files.

**Plan VII finished:** 2026-08-31T19:52Z (host clock; earlier entries used session-relative stamps). Commits: 734d976, 0705d09, 6205b5b.

## Nyquist results

Verified 2026-08-31 by jira-nyquist on the merged tree (branch jira/2026-08-31-live-episode-mvp). Evidence types: `command` (test or shell run live), `source-audit`/`artifact` (inspection). Server suite framework: ExUnit via `mix test`; web has no test runner by design — WEB-* verify via build/typecheck + source audit (accepted in 02-PLAN risks).

- [x] `mix ecto.create` exits 0 against Postgres 57432 (DEV-01) — command: `mix ecto.create` → "already been created", exit 0 (re-run live)
- [x] Phoenix boot log shows 127.0.0.1:57400 (DEV-02) — command: `mix phx.server` → "Running WhnWeb.Endpoint with Bandit 1.12.5 at 127.0.0.1:57400 (http)" (re-run live)
- [x] `.env` gitignored, shellHook sources it, `.env.example` committed (DEV-03) — source-audit: `git check-ignore .env` exit 0; `flake.nix:50-52` (PORT export + `set -a; . .env`); `git ls-files .env.example` tracked, documents FAL_KEY + CELERIS_KEY
- [x] README Development section names all four run commands (DEV-04) — source-audit: `README.md:445-450` (nix develop, pg-start, mix setup, mix phx.server, npm run dev)
- [x] `npm run build` exits 0 with SPA mode + phoenix 1.8.13 (WEB-01) — command: build + typecheck exit 0 (re-run live); source-audit: `web/vite.config.ts:10` `spa: { enabled: true }`, `web/package.json` phoenix "1.8.13"
- [x] Both players muted + playsInline behind a tap gate (WEB-02) — source-audit: `web/src/components/stage.tsx:141-167` (both `<video>` muted+playsInline; `tap-gate` button gates `started`)
- [x] Standby warms with `#t=0.001` + muted play/pause (WEB-03) — source-audit: `stage.tsx:76-86` (`fragmentSrc` default → `#t=0.001`, `muted = true`, `play().then(pause)`)
- [x] Poll bars animate width; countdown uses `deadline_ms + skewMs` (WEB-04) — source-audit: `web/src/components/vote-overlay.tsx:49,92` (width % bars, `deadlineMs - (now + skewMs)`); `web/src/styles.css:237` `transition: width 300ms ease`
- [x] Mount-time seek derives from `started_at_ms` across 10s segments (WEB-05) — source-audit: `stage.tsx:8-17,60-72` (`Date.now() + skewMs - started_at_ms`, floor/clamp across SEGMENT_MS)
- [x] `mix compile --warnings-as-errors` exits 0 with the 5-callback wrapper (FAL-01) — command: inside `mix precommit`, exit 0; dispatch of all five ops now asserted by `server/test/whn/fal_test.exs` (added in commit 4fc2409 — vision/2 had no test caller after the Celeris revision)
- [x] Frames test green using the local ffmpeg recipe (FAL-02) — command: `server/test/whn/frames_test.exs` (existing, 2 tests green)
- [x] fal-spike.log holds 5 per-stage wall-clock lines + total (FAL-03) — artifact: `.jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log` — 5 STAGE lines, TOTAL 27189ms, BUDGET CHECK within budget (untracked by design, `.jira/.gitignore` ignores *.log)
- [x] Join reply = full EpisodeSync (EP-01) — command: `server/test/whn_web/channels/episode_channel_test.exs` (existing)
- [x] presence_state keyed by anon_id (EP-02) — command: `episode_channel_test.exs` (existing)
- [x] Immutable one-vote policy at the channel (EP-03) — command: `episode_channel_test.exs` (existing; also at the server boundary in `episode_server_test.exs`)
- [x] Post-lock votes rejected with "locked" (EP-04) — command: `episode_channel_test.exs` (existing)
- [x] Open/lock timeline + lowest-index tie-break (EP-05) — command: `server/test/whn/episode_server_test.exs` (existing; a test-side race — stub read could beat the server's dispatch write under full-suite load — fixed with a sync barrier in commit b4d0a1e; implementation was correct)
- [x] Hold enters and exits as a state (EP-06) — command: `episode_server_test.exs` (existing)
- [x] Absolute epoch-ms clocks in payloads (EP-07) — command: `episode_server_test.exs` (existing)
- [x] Zero presence → pipeline not invoked, episode holds (EP-08) — command: `episode_server_test.exs` (existing)
- [x] Viewers present → start_opening invoked once with nil winning_choice/last_frame_url (EP-09) — command: `episode_server_test.exs` (existing)
- [x] `mix ecto.migrate` exits 0; four tables exist (DB-01) — command: migrate exit 0 ("Migrations already up"); information_schema lists episodes, beats, decisions, votes (re-run live)
- [x] Duplicate `(decision_id, anon_id)` cannot produce a second row (DB-02) — command: `server/test/whn/store_test.exs` (existing)
- [x] Episode/beat/decision/story-state round-trip (DB-03) — command: `store_test.exs` (existing)
- [x] §5 contract parses into the pinned result shape (CEL-01) — command: `server/test/whn/celeris_test.exs` (existing; Req.Test stub, no live calls)
- [x] Fenced/garbage LLM output → brace-slice / canned fallback, never a crash (CEL-02) — command: `celeris_test.exs` (existing)
- [x] Hygiene + sound rules in the system prompt; vertical suffix on every video_prompt (CEL-03) — command: `celeris_test.exs` (existing)
- [x] Stage messages arrive in pinned order (CEL-04) — command: `server/test/whn/pipeline_test.exs` (existing; FalMock, zero spend)
- [x] Reference param contract honored, seed = episode seed + beat (CEL-05) — command: `pipeline_test.exs` (existing; cycle + opening)
- [x] One idempotent retry per stage before error (CEL-06) — command: `pipeline_test.exs` (existing; fail-once, byte-identical retry)
- [x] Seed episode boots: row + registered server + phase broadcast (E2E-01) — command: `server/test/whn/integration_test.exs` (existing)
- [x] Driven cycle persists decisions/votes/beats with the locked winner (E2E-02) — command: `integration_test.exs` (existing)
- [x] `mix ecto.migrate`, `mix precommit`, `npm run build` all exit 0 on the merged tree (E2E-03) — command: all three re-run live post-additions, exit 0

Test suite: 37 passed / 37 total (`mix test`, 3 consecutive full runs green; was 35 before additions, with 1 intermittent failure from the EP-05 race). Commits: 4fc2409 (fal dispatch test), b4d0a1e (EP-05 race fix).

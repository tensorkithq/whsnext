---
sprint: 2026-08-31-live-episode-mvp
created: 2026-08-31
status: locked
---

# Context: 2026-08-31-live-episode-mvp

User's locked decisions for this sprint. Sourced from the session steering recorded at plan time (coordinator-relayed defaults are user-locked) plus planner discretion where noted. Once written here, decisions are NON-NEGOTIABLE for downstream agents.

## Phase boundary

This sprint delivers the MVP loop: one live episode where a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge + next scene via fal. Five tracks: (1) Phoenix episode core, (2) Postgres persistence, (3) fal generation pipeline in Elixir, (4) web TikTok/Instagram-vote experience, (5) devx wiring. It does NOT deliver accounts, comments, share cards, scheduling, replay, Redis/CDN/scaling, speculative branch generation, or backend-restart recovery (see Deferred ideas).

## Decisions

- **D-00 (goal restatement):** The sprint goal, measurable: one live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client. (Planner restatement of the brief goal; adds verification surface, reduces nothing.)
- **D-01 (vote policy):** One vote per `anon_id` per decision, **immutable** (Instagram-poll behavior: first write wins). A duplicate `vote` push replies `{:ok, %{tallies, your_vote}}` with tallies unchanged and `your_vote` = the original pick — not an error. Durable backstop: unique index on `(decision_id, anon_id)` + `Repo.insert(..., on_conflict: :nothing)`. Votes after lock reply `{:error, %{reason: "locked"}}`. *(session-locked)*
- **D-02 (tie-breaking):** At lock, winner = max tally; ties break to the **lowest option index** among tied leaders. Deterministic and trivially testable; ties are rare at MVP concurrency. *(planner discretion)*
- **D-03 (vote_update cadence):** Immediate per-accepted-vote `vote_update {tallies}` broadcast. No batching/throttle module this sprint. *(session-locked)*
- **D-04 (topic mapping):** Client topic stays `"episode:live"`. The channel resolves `"live"` to the single currently-running episode via `Whn.Episodes.current/0` (Registry-backed). Any other `episode:*` subtopic rejects the join. *(session-locked)*
- **D-05 (Celeris model) — REVISED 2026-08-31:** Celeris is the real Celeris API (user provided `CELERIS_KEY` in `.env`): OpenAI-compatible chat completions at `https://inference.celeris.ai/celeris-1/v1/chat/completions`, header `Authorization: Bearer $CELERIS_KEY`, `model: "celeris-1"`, `temperature: 0.6`, `max_tokens: 700`, `seed` passthrough supported. Text-only (vision undocumented) — **no frame attachment**; the script engine runs on explicit story state per README §5, which is the brief's stated design anyway. JSON mode undocumented → prompt discipline + brace-slice parsing (unchanged). Smoke-tested this session: a §5-shaped request returned clean compact JSON (90 completion tokens, `finish_reason: "stop"`). Keep prompts tight — reported combined context is 8,192 tokens (secondary source). Pricing $2/M in, $6/M out. *Original decision (fal `openrouter/router/vision` + `google/gemini-2.5-flash-lite`, frame attached) is demoted to documented fallback only; `Whn.Fal.vision/2` stays for the spike and as that fallback.* *(user-locked)*
- **D-06 (frame extraction):** Local ffmpeg (flake devshell) on the critical path: download mp4 with Req → `ffmpeg -y -sseof -0.25 -i clip.mp4 -frames:v 1 -q:v 3 last.jpg` → `FalEx.Storage.upload` → hosted URL used as i2v `image_url`. Hosted `fal-ai/ffmpeg-api/extract-frame` is a documented alternative only — not built. *(session-locked)*
- **D-07 (hold state):** `hold` is a first-class phase, not an error. Server broadcasts `phase "hold"` when the current playback ends with nothing ready; client freezes on the last available frame with a shimmer treatment; the next `playback` broadcast resumes `live`. *(session-locked)*
- **D-08 (phoenix npm):** Bump web `phoenix` to `1.8.13` (matches server). `@types/phoenix` stays `^1.6.7`. *(session-locked)*
- **D-09 (ports):** Postgres `port: 57432` pinned in Repo config in BOTH `dev.exs` and `test.exs` (Postgrex ignores PGPORT). Phoenix HTTP 57400 three ways: `http: [port: 57400]` in `dev.exs`, the `runtime.exs` PORT fallback default changed `"4000"` → `"57400"` (runtime.exs executes after dev.exs and would otherwise override the pin), and `export PORT=57400` in the flake shellHook. *(session-locked; runtime.exs default added by planner because the env fallback overrides dev.exs)*
- **D-10 (web re-bootstrap):** `web/` is re-bootstrapped as a **fresh TanStack Start scaffold in SPA mode** (`tanstackStart({ spa: { enabled: true } })` in vite config). Ported forward: `src/lib/{types,useEpisode,identity}.ts` verbatim protocol, the `/socket` (ws) + `/api` proxy to `127.0.0.1:57400`, and the `index.html` title/viewport meta. No Start server functions/SSR — Phoenix owns the backend. *(session-locked)*
- **D-11 (fal client):** `fal_ex ~> 0.1.0` (user-mandated), isolated behind the `Whn.Fal` behaviour + configured impl so a thin Req fallback stays a one-file swap. `{:req, "~> 0.5"}` added for mp4 downloads (AGENTS.md mandates Req for hand-written HTTP). *(session-locked)*
- **D-12 (cost guard):** No generation cycle starts while the viewer count (Presence) is 0; the episode holds and rechecks. Prevents an unattended episode generating ~$2.00/cycle forever. *(from RESEARCH pitfall; planner-locked)*
- **D-13 (seed episode):** Lagos Wahala — "Salary Just Entered" (PLOT.md §3–4) is the seed content: premise, protagonist, initial story state (money/relationships/active problems), opening prompt. *(BRIEF-locked)*
- **D-14 (timing model):** Scene = 30s as 3×10s segments; vote opens at scene start +10s; window 10s; lock at +20s; bridge target duration 10s (Celeris may return 8–12, clamped). All timings live in EpisodeServer state (test-injectable), transitions are explicit `{:timeline, event}` self-messages scheduled with `Process.send_after` so tests drive them manually. *(README §2-locked; test shape per server/AGENTS.md)*
- **D-15 (failure policy):** Each fal generation stage retries **once** with the same seed (idempotency), then the pipeline reports `{:error, stage, reason}`. Celeris retries once, then substitutes the canned fallback result. A vote is never reopened by a generation failure (README §12). *(README §12-locked; retry counts planner discretion)*
- **D-16 (secrets):** `FAL_KEY` lives in `.env` at the repo root (already gitignored), auto-sourced by the flake shellHook (`set -a`). A committed `.env.example` documents the shape. No plan may require committing a secret. *(session-locked)*

## Claude's discretion

- Tie-breaking rule (D-02) — lowest index; revisit with real audience data.
- Retry counts in D-15 (once per stage) and Celeris call budget (temperature 0.6, max_tokens 700, mirroring the reference adjudicator).
- Module/interface names in "Pinned interfaces" below — invented by the planner so parallel plans compose without file overlap.
- Per-segment prompting: the 3 scene segments reuse `next_scene.video_prompt` with a "continuation, part n of 3" suffix; continuity comes from frame chaining + `prompt_expansion_mode: "disabled"`.
- Vote rows persist per-vote fire-and-forget (Task.Supervisor) rather than batch-at-lock — the unique index makes this safe.

## Pinned interfaces (cross-plan contracts — conform exactly)

Parallel plans compose only through these. Do not rename.

**Wire protocol** — canonical source: `web/src/lib/types.ts` + `web/src/lib/useEpisode.ts` (frozen; server conforms to client). Topic `episode:live`; join reply `EpisodeSync {phase, episode: {title, premise} | null, now_ms, playback, vote}`; broadcasts `phase {phase}`, `playback {kind, beat, segments, started_at_ms}`, `preload {urls}`, `vote_open VoteState`, `vote_update {tallies}`, `vote_locked {winner_idx, tallies}`, `vote_closed {}`; push `vote {option_idx}` → ok `{tallies, your_vote}` / error `{reason: "locked"}`. All `*_ms` fields are absolute server epoch milliseconds.

**`Whn.Fal`** (behaviour + public module; impl resolved via `Application.get_env(:whn, :fal_impl, Whn.Fal.FalEx)`):

```elixir
@callback t2v(prompt :: String.t(), opts :: keyword()) :: {:ok, %{url: String.t()}} | {:error, term()}
@callback i2v(prompt :: String.t(), image_url :: String.t(), opts :: keyword()) :: {:ok, %{url: String.t()}} | {:error, term()}
@callback flux(prompt :: String.t(), opts :: keyword()) :: {:ok, %{url: String.t()}} | {:error, term()}
@callback vision(prompt :: String.t(), opts :: keyword()) :: {:ok, %{output: String.t()}} | {:error, term()}
@callback upload(path :: Path.t()) :: {:ok, String.t()} | {:error, term()}
```

Endpoints: t2v `minimax/h3-max/text-to-video`, i2v `minimax/h3-max/image-to-video`, flux `fal-ai/flux-2-pro`, vision `openrouter/router/vision`. Opts pass through: `duration`, `resolution`, `aspect_ratio`, `seed`, `prompt_expansion_mode`, `image_size`, `model`, `system_prompt`, `image_urls`, `temperature`, `max_tokens`.

**`Whn.Frames.last_frame(video_url) :: {:ok, frame_url} | {:error, term()}`** — Req download → ffmpeg per D-06 → `Whn.Fal.upload`.

**Pipeline boundary** — impl resolved via `Application.get_env(:whn, :pipeline_impl, Whn.Pipeline)`, invoked dynamically (no compile-time dependency from the EpisodeServer):

```elixir
@callback start_opening(dest :: pid(), ctx :: map()) :: {:ok, pid()} | {:error, term()}
@callback start_cycle(dest :: pid(), ctx :: map()) :: {:ok, pid()} | {:error, term()}
# ctx: %{beat, seed, episode: %{title, premise}, story_state, winning_choice (nil for opening),
#        last_frame_url (nil for opening), history: [scene_summary, oldest first]}
# messages sent to dest:
#   {:pipeline, beat, {:celeris, result}}           # result per README §5, atom keys; bridge: nil for opening
#   {:pipeline, beat, {:bridge_ready, url}}
#   {:pipeline, beat, {:segment_ready, seg_idx, url}}  # seg_idx 0..2, in order
#   {:pipeline, beat, {:error, stage, reason}}      # stage ∈ :celeris | :bridge | :frame | :segment
```

**Episode lookup** — `Whn.Episodes.current() :: pid() | nil`; `Whn.EpisodeServer.join_sync(pid, anon_id) :: EpisodeSync map`; `Whn.EpisodeServer.vote(pid, anon_id, option_idx) :: {:ok, %{tallies: [integer()], your_vote: integer()}} | {:error, :locked} | {:error, :no_open_vote}`.

**Supervision names** (registered in `application.ex` by the episode-core plan): `Whn.EpisodeRegistry` (Registry, unique keys), `Whn.EpisodeSupervisor` (DynamicSupervisor), `Whn.TaskSupervisor` (Task.Supervisor), `WhnWeb.Presence` (`use Phoenix.Presence, otp_app: :whn, pubsub_server: Whn.PubSub`).

**Store** — sync context functions (persistence plan): `Whn.Store.create_episode(attrs)`, `Whn.Store.upsert_beat(episode_id, attrs)`, `Whn.Store.record_decision(episode_id, attrs)`, `Whn.Store.record_vote(decision_id, anon_id, option_idx)` (on_conflict per D-01), `Whn.Store.update_story_state(episode_id, map)`. Async wrapping happens at integration time, not inside Store.

## Deferred ideas

- Accounts/OAuth, device fingerprinting → future (anonymous identity only this sprint)
- Comments, share cards, episode scheduling/cadence (5/day), replay mode → future
- Redis, CDN infrastructure, horizontal scaling → future
- Speculative generation of all vote branches → never for MVP (winner-only, README §3)
- Backend-restart timeline reconstruction (recovery flow) → future sprint (persist yes, recover no)
- fal webhook mode (`?fal_webhook=`) → prod optimization; polling via `FalEx.subscribe` this sprint
- `vote_update` batching/throttling → only if concurrency demands it
- Hosted `fal-ai/ffmpeg-api/extract-frame` → fallback documented, not built

## Canonical references

- `web/src/lib/types.ts`, `web/src/lib/useEpisode.ts` — the frozen wire protocol; server conforms to these.
- `README.md` §2 (timing), §3 (winner-only pipeline), §5 (Celeris JSON contract), §9 (no video proxying; dual player), §11 (persistence), §12 (failure matrix).
- `PLOT.md` §3–6, §15 — seed episode content, choice-quality rules, bridge vocabulary, plot-engine continuity rules.
- `tmp/interdimensional-game/lib/fal.ts` — fal param contract (endpoints, seed+beat, prompt_expansion_mode, response shapes).
- `tmp/interdimensional-game/lib/adjudicator.ts` — LLM-JSON parse/clamp/fallback discipline; FINAL FRAME HYGIENE rule; `worlds.ts:220-221` SOUND_CLAUSE.
- `tmp/interdimensional-game/experiments/grab-frames.mjs` — ffmpeg last-frame recipe.
- `server/AGENTS.md` — Elixir/Phoenix/Ecto/test rules binding on all server plans (start_supervised!, no Process.sleep, programmatic fields never in cast, mix ecto.gen.migration).
- `.jira/sprints/2026-08-31-live-episode-mvp/RESEARCH.md` (+ research-codebase/patterns/external.md) — verified facts and pitfalls.

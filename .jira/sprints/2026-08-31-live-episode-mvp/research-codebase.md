# Research: codebase — 2026-08-31-live-episode-mvp

## Summary

- The reference impl (`tmp/interdimensional-game`) runs the entire pipeline **in the browser**: fal calls via `fal.subscribe` through a Next.js key proxy, last-frame extraction via `<canvas>`, per-client `setTimeout` timers, per-run random seeds, and speculative pre-generation of all 3 branches. All of that inverts in the multi-user version — generation, frames, timers, and seeds move server-side; branch pre-generation is explicitly out of scope (winner-only, BRIEF constraint / README §3).
- Exact fal params to reproduce: `minimax/h3-max/text-to-video` and `.../image-to-video` with `{prompt, duration, resolution: "480P", seed: seed+beat, prompt_expansion_mode: "disabled"|"balanced"}` plus `image_url` (i2v) or `aspect_ratio` (t2v); vision LLM at `openrouter/router/vision` with model `google/gemini-2.5-flash-lite`. Measured latency in reference comments: a 480P/10s clip generates in ~6-8s (`tmp/interdimensional-game/lib/types.ts:6`).
- The wire protocol is already drafted in `web/src/lib/types.ts` + `useEpisode.ts`: join reply `EpisodeSync {phase, episode, now_ms, playback, vote}`; broadcasts `phase`, `playback`, `preload`, `vote_open`, `vote_update`, `vote_locked`, `vote_closed`; client push `vote {option_idx}` → reply `{tallies, your_vote}`. The Phoenix side implements none of it yet.
- Scaffold gaps: server has no socket/channel/presence modules and no migrations; `dev.exs` Repo config lacks `port: 57432`; HTTP port resolves to 4000 (via `runtime.exs` PORT default) but Vite proxies to 57400; `web/index.html` references `/src/main.tsx` which does not exist (no entrypoint, routes, or components committed); `server/AGENTS.md` says Req is available but `mix.exs`/`mix.lock` do not include it.
- Server-side last-frame extraction already has a working ffmpeg recipe in the reference: `ffmpeg -sseof -0.25 -i clip.mp4 -frames:v 1 -q:v 3 out.jpg` (`tmp/interdimensional-game/experiments/grab-frames.mjs:7-13`); `flake.nix:33` provides ffmpeg.

## Findings

### Reference impl: fal pipeline (`tmp/interdimensional-game/lib/fal.ts`)

Endpoints and model IDs (fal.ts:10-14):
- `T2V_ENDPOINT = "minimax/h3-max/text-to-video"`
- `I2V_ENDPOINT = "minimax/h3-max/image-to-video"`
- `VISION_ENDPOINT = "openrouter/router/vision"`, `VISION_MODEL = "google/gemini-2.5-flash-lite"`
- Opening-frame image model: `fal-ai/flux-2-pro` with `{prompt, image_size: {width: 1280, height: 720}, seed, output_format: "jpeg"}` (fal.ts:74-81). For vertical, image_size must flip to 720x1280.

`filmShot` input contract (fal.ts:40-53) — the exact params the Elixir port must reproduce:
```
prompt, duration (seconds, reference uses 10), resolution ("480P" default, "768P" option),
seed: runSeed + beat  (varied per beat so near-identical prompts diverge),
prompt_expansion_mode: "disabled" when chaining from a frame, "balanced" for cold t2v opens
i2v only: image_url (a data-URI of the previous last frame works)
t2v only: aspect_ratio: "16:9"  → must become "9:16" for the vertical product
```
Response shape: `result.data.video.url` (fal.ts:58-60). Transport is `fal.subscribe` from `@fal-ai/client` ^1.5.0 (package.json) — this wraps fal's queue API + status polling; Elixir must talk to the queue REST API directly (no official Elixir client; see external research).

Vision call contract (fal.ts:99-108): input `{model, system_prompt, prompt, image_urls: [dataUri...], temperature, max_tokens}`, output at `result.data.output` (string). `extractJson` (fal.ts:113-118) slices first `{` to last `}` — the standard defence against markdown-fenced replies.

Moderation (app/api/moderate/route.ts) shows the **raw HTTP** shape for synchronous fal calls: `POST https://fal.run/fal-ai/any-llm` with header `Authorization: Key ${FAL_KEY}` and body `{model, system_prompt, prompt, temperature, max_tokens, priority: "latency"}` (route.ts:49-64). Fail-closed on any error (route.ts:73-76). Moderation itself is out of MVP scope (no free-text actions).

### Reference impl: frame extraction (`lib/frames.ts`, `experiments/grab-frames.mjs`)

Client-side today: hidden `<video>` + canvas, seeks to 0.01 / duration/2 / duration-0.05, grabs JPEG data-URIs — 512-768px strips for vision calls, full-res `lastFrame` at quality 0.92 as the next shot's `image_url` (frames.ts:44-90). **Does not translate**: requires a browser, and required the same-origin media proxy purely to un-block canvas CORS (app/api/media/route.ts:3-4).

Server-side equivalent already proven in the repo: `grab-frames.mjs:7-13` extracts start/mid/end frames with ffmpeg — last frame via `-sseof -0.25 -i file -frames:v 1 -q:v 3`. This is the recipe for the Elixir pipeline (download clip → ffmpeg → upload/inline frame as i2v `image_url`).

### Reference impl: vision-LLM contract patterns (`lib/adjudicator.ts`, `lib/witness.ts`, `lib/referee.ts`)

The Celeris engine (README §5) has a different JSON schema, but the parsing/robustness patterns are directly portable:
- Strict "Return ONLY compact JSON, no markdown fences, exactly this shape: {...}" system prompts (adjudicator.ts:22-23, referee.ts:17-18).
- Every field defensively parsed and clamped: strings truncated (`str(value, max)` adjudicator.ts:62-64), numerics rounded + clamped (`hp_delta` to [-50, 20], adjudicator.ts:155-159), enums defaulted (`asRisk` → "safe" adjudicator.ts:66-68; referee risk defaults "risky" referee.ts:73-76), arrays sliced to max length (options `.slice(0, 3)` adjudicator.ts:73).
- Validity gates: a verdict without a synopsis or with <2 options returns `null` (adjudicator.ts:152-153, 186).
- Every LLM call returns `null` on failure and the caller substitutes a canned fallback so the loop never stalls (`fallbackVerdict` adjudicator.ts:219-252) — maps to README §12 "retry structured generation without reopening vote".
- Call budgets: adjudicator maxTokens 700 / temp 0.6 (adjudicator.ts:146-148); witness 240 / 0.1 (witness.ts:35-36); referee 300 / 0.7 (referee.ts:55-56).
- Prompt-continuity grammar: world `camera` + `SOUND_CLAUSE` + `style` tokens appended to every generated shot prompt (adjudicator.ts:80-87). `SOUND_CLAUSE` (worlds.ts:220-221): "Sound: ambient environmental audio and cinematic score only; any voices are wordless… no spoken dialogue" — H3 Max babbles pseudo-language otherwise (worlds.ts:215-218). "FINAL FRAME HYGIENE" rule (adjudicator.ts:40): prompts must end readable because the last frame seeds the next shot — directly applicable to bridge→scene chaining.

Witness/referee/dice/free-text/items/HP are single-player game mechanics with no MVP counterpart — reference-only.

### Reference impl: engine (`lib/engine.ts`) — what ports, what dies

Ports conceptually to the `EpisodeServer` GenServer:
- Token-guarded async: every continuation checks `token !== this.token` (and beat) so stale results never clobber state (engine.ts:94-99, 235, 311, 490). GenServer refs/`handle_info` tagging is the Elixir analogue.
- Verdict runs during playback: adjudication starts as soon as the clip lands, applies when the clip ends (`pendingVerdict`/`clipEnded` engine.ts:100-103, 337-350). Same overlap trick the README §3 latency budget depends on.
- Filming failure mid-run falls back to the choice phase instead of dying (engine.ts:283-293).

Does NOT translate:
- Whole pipeline runs client-side; each browser generates its own video with its own random seed (engine.ts:142) — multi-user needs one server-owned seed and one canonical clip per beat.
- `choiceDeadline: Date.now() + windowMs` + local `setTimeout` (engine.ts:471, 503-508) — per-client clocks; brief requires server-synchronized deadline (already drafted as `deadline_ms` + `skewMs` in web scaffold).
- All-3-branch pre-generation (engine.ts:476-501) — explicitly out of scope; winner-only.
- `worldActsInARow` idle guard (engine.ts:106-109, 524-535) — single-player concept; a live episode always advances.
- Playback state via `onClipEnded` DOM event (engine.ts:341) — server must own the playback clock instead (`started_at_ms` in the drafted protocol).
- `/api/fal/proxy` (browser→fal key proxy, app/api/fal/proxy/route.ts:1-4) and `/api/media` (CORS-unblocking byte proxy, app/api/media/route.ts) both die: FAL_KEY lives in the Elixir server, clients get raw `fal.media` CDN URLs (BRIEF constraint, README §9). The media proxy's host allowlist (`fal.media` / `*.fal.media`, media/route.ts:12-17) remains useful as a validation pattern if URLs are ever echoed.

Timing evidence (HIGH value for the planner): "a 480P/10s branch films in ~6-8s, 768P in ~12s" (types.ts:5-7, stated as measured); `SHOT_SECONDS = 10` (types.ts:18). So the README §2 model (lock at ~20s; 10s remaining scene + 10-12s bridge as budget) leaves room for bridge gen (~6-8s) + last-frame extract + first next-scene segment (~6-8s), and each subsequent 10s segment can generate while the previous one plays.

### Committed scaffold: `server/` (phx.new, channels-only)

- Deps (mix.exs:40-52): phoenix 1.8.13, phoenix_ecto 4.7, ecto_sql 3.14, postgrex 0.22.4, bandit 1.12.5, jason, telemetry, dns_cluster (versions from mix.lock). **No HTTP client** (no req/finch/tesla) despite `server/AGENTS.md:6` claiming Req is included — a dep must be added for fal calls.
- Supervision tree (lib/whn/application.ex:10-19): Telemetry, `Whn.Repo`, DNSCluster, `{Phoenix.PubSub, name: Whn.PubSub}`, Endpoint — with an explicit comment slot where `EpisodeServer` supervision plugs in (application.ex:15-16).
- Endpoint (lib/whn_web/endpoint.ex): **no socket mounted** — only a commented-out LiveView socket (endpoint.ex:14-16). `socket "/socket", WhnWeb.UserSocket` must be added; no UserSocket, channel, or Presence module exists anywhere in `server/lib` (grep confirms only the `whn_web.ex:32-35` `channel` macro helper). Phoenix.Presence ships inside phoenix itself, so no new dep — just a `Whn.Presence` module + supervision child.
- Router (lib/whn_web/router.ex:8-10): empty `/api` scope, JSON-only pipeline.
- HTTP port: dev.exs sets `http: [ip: {127,0,0,1}]` with **no port** (dev.exs:22); runtime.exs:23 supplies `http: [port: PORT env || 4000]` for all envs. Vite proxies to `http://127.0.0.1:57400` (web/vite.config.ts:6). Either export `PORT=57400` (flake shellHook currently does not) or pin the port in dev.exs.
- Database: dev.exs:4-11 (`whn_dev`, user postgres, hostname localhost, **no :port**) and test.exs:8-14 (`whn_test`, no :port) default to 5432; flake Postgres listens on 57432 (`flake.nix:14,21,45`) — `port: 57432` must be added (Postgrex does not read PGPORT). `initdb --auth=trust` (flake.nix:19) makes the `password: "postgres"` value inert.
- `check_origin: false` in dev (dev.exs:23) — WebSocket origin checks won't bite in dev; the Vite proxy makes /socket and /api same-origin anyway, so no CORS work needed for dev.
- Migrations: `priv/repo/migrations/` empty (only `.formatter.exs`) — episodes/beats/decisions/votes schema is greenfield.
- `mix precommit` alias exists (mix.exs:66); `server/AGENTS.md` carries full Phoenix 1.8 usage-rules (LiveView-slanted; channels-relevant Elixir rules still apply).

### Committed scaffold: `web/` (Vite + React SPA)

- Deps (package.json:12-25): react 19.1, @tanstack/react-router ^1.130, phoenix (JS client) ^1.7.21, vite 6.3.5, TS 5.7.3. Note version skew: phoenix.js 1.7.x client vs server phoenix 1.8.13 (wire-compatible in practice, but worth pinning consciously). No CSS framework, no test runner.
- Drafted wire protocol (src/lib/types.ts:1-35) — the contract the Phoenix channel must implement, verbatim:
  - `Phase = "idle" | "opening" | "live" | "hold" | "ended"` (types.ts:3)
  - `Playback {kind: "scene"|"bridge", beat, segments: string[] /* direct fal CDN URLs, one per 10s segment, play order */, started_at_ms /* server epoch ms when segment 0 started */}` (types.ts:7-14)
  - `VoteState {question, options: string[], tallies: number[], deadline_ms, locked, winner_idx: number|null, your_vote: number|null}` (types.ts:16-24)
  - Join reply `EpisodeSync {phase, episode: {title, premise}|null, now_ms, playback, vote}` (types.ts:26-32); `SEGMENT_SECONDS = 10` (types.ts:34)
- Channel hook (src/lib/useEpisode.ts): socket at `/socket` with `params: {anon_id}` (useEpisode.ts:33); channel topic `"episode:live"` (:36); `Presence` synced to a viewer count (:39-40); handlers for `phase {phase}`, `playback Playback` (clears preload), `preload {urls}`, `vote_open VoteState`, `vote_update {tallies}`, `vote_locked {winner_idx, tallies}`, `vote_closed` (:42-66); join reply computes `skewMs = sync.now_ms - Date.now()` (:72); push `"vote" {option_idx}` expects reply `{tallies, your_vote}` (:87-94).
- Identity (src/lib/identity.ts:1-14): `localStorage["whn:anon-id"]` ← `crypto.randomUUID()`, falls back to ephemeral UUID when storage is unavailable — matches README §10.
- Vite (vite.config.ts:15-21): `host: true`, proxies `/socket` (ws) and `/api` to 127.0.0.1:57400; `@` → `./src` alias.
- **Missing**: `index.html:14` loads `/src/main.tsx`, which does not exist; no router setup, routes, components, or CSS anywhere — `src/lib/` is the only src directory. Title already set: "Lagos Wahala — Live" (index.html:11).

### `flake.nix` toolchain

Packages (flake.nix:30-37): `elixir` (nixpkgs unstable, unpinned version), `nodejs_24`, `ffmpeg`, `postgresql_17`, `pg-start`/`pg-stop` helper scripts, `inotify-tools` on Linux (Phoenix live reload). shellHook (flake.nix:40-48): local `MIX_HOME`/`HEX_HOME` (`.nix-mix`/`.nix-hex`), `PGPORT=57432`, `PGDATA=$PWD/.nix-postgres`, `PGHOST=127.0.0.1`, `PGUSER=postgres`. `pg-start` (flake.nix:16-22): initdb trust auth, listens 127.0.0.1 on $PGPORT with socket dir in PGDATA. **Not exported**: `PORT` (Phoenix HTTP), `FAL_KEY`, any DATABASE_URL.

### README.md / PLOT.md anchor points

- README §2: cycle timing (30s scene, vote UI ~10s, 10s window, lock ~20s); §3: winner-only pipeline diagram + "remaining scene + bridge playback = generation latency budget"; §4: MiniMax H3 Max @480p, continuity inputs; §5: Celeris JSON contract `{scene_summary, winning_choice, bridge{duration,script,video_prompt}, next_scene{duration,script,video_prompt}, next_choices[], story_state_updates{}}`; §6: canonical story-state fields, "rejected options never become story truth"; §7: Phoenix responsibilities + one EpisodeProcess per episode + PubSub fan-out; §9: no video-byte proxying, active/standby dual player; §10: anon identity; §11: Postgres tables list, no Redis; §12: failure matrix (video-not-ready, generation retry w/ idempotency, Celeris retry without reopening vote, reconnect sync, duplicate vote policy, restart persistence).
- PLOT.md §3-4: Lagos Wahala / "Salary Just Entered" premise (salary lands; landlord, mother, friend's proposal, commute, relationship); §5: choice conditions (understandable / debatable / consequential; avoid correct-or-stupid options); §6: story rhythm + bridge vocabulary (walking, phone answer, entering vehicle, knocking…) — direct source material for Celeris prompt engineering; §15: plot-engine continuity rules (callbacks, resource depletion, consequences resurfacing).
- Note the reference stage uses a **single** `<video>` keyed by URL + freeze-frame `<img>` (components/stage.tsx:34-46), not the dual active/standby player README §9 requires — the web track builds that fresh.

### Architectural Responsibility Map (seed)

| Capability | Today (reference impl) | Target per brief |
|---|---|---|
| fal generation calls + FAL_KEY | Browser via Next proxy (fal.ts:6, api/fal/proxy) | Phoenix pipeline (API/Backend) |
| Last-frame extraction | Browser canvas (frames.ts) | Phoenix + ffmpeg (grab-frames.mjs recipe) |
| Script/story LLM | Browser (adjudicator.ts) | Phoenix Celeris module (README §5) |
| Vote/choice timer | Per-client setTimeout (engine.ts:503) | EpisodeServer, broadcast deadline_ms |
| Vote counting / one-per-id | n/a (single player) | Channel + EpisodeServer, anon_id socket param |
| Playback clock | DOM onEnded (engine.ts:341) | Server started_at_ms + client skew |
| Video bytes | Same-origin proxy (api/media) | Direct fal.media CDN → client preload |
| Presence/viewer count | n/a | Phoenix.Presence (client hook already reads it) |
| Persistence | none (all in-memory browser state) | Ecto/Postgres 57432 (README §11) |
| Story premise/content | worlds.ts presets | Lagos Wahala seed (PLOT.md §3-4) |

## Open questions

- fal queue REST semantics from Elixir (submit/status/result URLs, webhooks vs polling) — external-research territory; the reference only shows the JS `fal.subscribe` abstraction and one raw `https://fal.run/<endpoint>` sync call (moderate/route.ts:49).
- Does `minimax/h3-max/image-to-video` accept 10s `duration` and inherit aspect from `image_url` (reference never passes aspect_ratio on i2v)? And does it accept an HTTPS frame URL as `image_url`, or must the Elixir side upload/inline data-URIs as the browser did? — external.
- "Celeris" model identity/endpoint: nothing in the repo maps the name to a concrete fal/OpenRouter model id; the reference's closest analogue is `openrouter/router/vision` + `google/gemini-2.5-flash-lite` (fal.ts:13-14) and `fal-ai/any-llm` (moderate/route.ts:9). Needs a decision or external confirmation.
- Elixir version pinning: flake uses nixpkgs-unstable `elixir` while mix.exs requires `~> 1.17` — actual version drifts with the flake lock; no `.tool-versions`.
- `vote_update` broadcast cadence (per-vote vs throttled) and whether `preload` fires per-segment or once per scene — the drafted client accepts either; server design decision.
- Whether the join reply's `Playback.started_at_ms` is enough for mid-scene reconnect (README §12 wants "current canonical scene, playback timestamp") — the drafted types suggest yes, but seeking a `<video>` to `(now_ms - started_at_ms)` across segment boundaries needs client logic that doesn't exist yet.

## Sources

### Primary (HIGH confidence)
All read directly from the repo:
- /home/drew/kit/whn/tmp/interdimensional-game/lib/fal.ts (endpoints :10-14, filmShot :30-65, paintFrame :73-86, visionCall :91-110, extractJson :113-118)
- /home/drew/kit/whn/tmp/interdimensional-game/lib/frames.ts (:44-90), lib/adjudicator.ts (:16-45, :62-88, :143-213, :219-252), lib/witness.ts (:16-43), lib/referee.ts (:14-85), lib/engine.ts (:90-766), lib/types.ts (:1-27, :96-140), lib/worlds.ts (:6-40, :215-223)
- /home/drew/kit/whn/tmp/interdimensional-game/app/api/{fal/proxy,media,moderate}/route.ts; experiments/grab-frames.mjs (:7-13); components/stage.tsx (:34-46); package.json; .env.example
- /home/drew/kit/whn/server/{mix.exs,mix.lock,config/config.exs,config/dev.exs,config/test.exs,config/runtime.exs,lib/whn/application.ex,lib/whn_web/endpoint.ex,lib/whn_web/router.ex,lib/whn_web.ex,AGENTS.md}
- /home/drew/kit/whn/web/{package.json,vite.config.ts,index.html,src/lib/types.ts,src/lib/useEpisode.ts,src/lib/identity.ts}
- /home/drew/kit/whn/flake.nix; /home/drew/kit/whn/README.md (§2,3,4,5,6,7,9,10,11,12); /home/drew/kit/whn/PLOT.md (§3,4,5,6,15)

### Secondary (MEDIUM confidence)
- 480P/10s ≈ 6-8s generation latency: stated as measured in reference comments (types.ts:5-7) but not re-verified; treat as planning estimate.
- Phoenix.Presence requiring no extra hex dep (ships in phoenix); phoenix.js 1.7 client ↔ phoenix 1.8 server wire compatibility; runtime.exs deep-merging `http: [port:]` over dev.exs `http: [ip:]` — standard Phoenix/Config behavior, inferred from framework knowledge, not tested in this repo.
- Postgrex ignoring PGPORT env (needs explicit `port:` in config) — framework knowledge.

### Tertiary (LOW confidence)
- Pipeline feasibility math (segment N+1 generating while segment N plays keeps the 30s scene seamless) — inferred from the 6-8s figure plus README §2 timings; needs validation against real fal queue latency including download+ffmpeg+upload overhead.

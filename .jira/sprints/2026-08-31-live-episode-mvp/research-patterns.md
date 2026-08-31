# Research: patterns — 2026-08-31-live-episode-mvp

## Summary

- The Phoenix scaffold is channels-ready but nothing is wired: `WhnWeb.channel/0` helper exists, yet there is no socket mount in the endpoint, no channels dir, no Presence, no DynamicSupervisor/Registry, and `:req` is absent from deps despite `server/AGENTS.md` mandating it.
- The web client already fixes the wire protocol: `web/src/lib/types.ts` + `useEpisode.ts` define the channel topic (`episode:live`), event names (`phase`, `playback`, `preload`, `vote_open`, `vote_update`, `vote_locked`, `vote_closed`), join-reply sync shape with `now_ms` skew, and a `vote` push expecting `{tallies, your_vote}`. Server implementation must conform to this, not the other way around.
- The reference impl (`tmp/interdimensional-game`) is the richest pattern source: token/beat guards against stale async, seed-per-beat discipline, `prompt_expansion_mode` rules for frame chaining, `-sseof` last-frame extraction, lenient LLM-JSON parsing with fallback, "freeze-frame instead of spinner" seam-hiding, and rAF-driven countdown bars.
- Deliberate non-imitations: the reference's same-origin media proxy (exists only for canvas CORS; server-side ffmpeg removes the need and the brief forbids proxying video), its unmuted `<video autoPlay>` (breaks on mobile), its single-`<video>` element (brief requires active/standby pair), and its client-side authority over timers (server owns all clocks here).
- Local near-misses found: vite proxy targets port 57400 while `dev.exs` uses default 4000; `dev.exs` points at Postgres 5432 while the flake runs it on 57432; no `backdrop-filter` exists anywhere in the reference CSS, so the Instagram frosted-glass look is net-new (the width-percentage bar mechanic, however, exists twice).

## Findings

### Phoenix/OTP conventions (Patterns & conventions)

**Supervision tree today.** `server/lib/whn/application.ex:10-19` — children are Telemetry, Repo, DNSCluster, `{Phoenix.PubSub, name: Whn.PubSub}`, Endpoint. New children (Presence, Registry, DynamicSupervisor, Task.Supervisor) slot between PubSub and Endpoint; the generated comment at `application.ex:15-16` marks the conventional insertion point.

**Presence conventions** (HIGH — read from vendored docs, `server/deps/phoenix/lib/phoenix/presence.ex:24-64`):
- Module: `use Phoenix.Presence, otp_app: :whn, pubsub_server: Whn.PubSub`; conventional path in a 1.7/1.8 app is `lib/whn_web/channels/presence.ex` (alongside `user_socket.ex`, `episode_channel.ex`).
- Must sit in the supervision tree *after PubSub and before the endpoint* (presence.ex:34-43).
- Track in an `:after_join` `handle_info` (`send(self(), :after_join)` from `join/3`), then `push(socket, "presence_state", Presence.list(socket))` (presence.ex:47-65). Diffs go out as `presence_diff` automatically.
- Keep metas minimal/ephemeral (presence.ex:99-101). For viewer counts, key = `anon_id`, meta = `%{online_at: ...}` suffices.
- Client side is already conformant: `web/src/lib/useEpisode.ts:39-40` builds `new Presence(channel)` and counts `presence.list().length` on sync. Note: keying by anon_id means N tabs of one browser count as 1 viewer — a property, not a bug, but worth stating.

**Channel/socket layout.** `server/lib/whn_web.ex:32-36` already provides the `use WhnWeb, :channel` helper. `server/lib/whn_web/endpoint.ex` has *no* `socket` mount (only the commented LiveView one at endpoint.ex:14-16) — a `socket "/socket", WhnWeb.UserSocket, websocket: true, longpoll: false` line is required; the client connects to `/socket` passing `{params: {anon_id}}` (`useEpisode.ts:33`), and vite proxies `/socket` with `ws: true` (`web/vite.config.ts:18`). Topic routing via `channel "episode:*", WhnWeb.EpisodeChannel` in the socket module (pattern documented at `server/deps/phoenix/lib/phoenix/socket.ex:20,42`). The anon_id arrives in `connect/3` params and belongs in socket assigns, not per-message payloads.

**Join reply as full sync state** (HIGH — `server/deps/phoenix/lib/phoenix/channel.ex:370-373`): `join/3` may return `{:ok, reply, socket}`. The client expects exactly this: join `receive("ok")` consumes an `EpisodeSync` — `{phase, episode, now_ms, playback, vote}` (`useEpisode.ts:70-77`, `types.ts:26-32`). This one shape covers both late joiners and reconnects (README.md:381-383 "Viewer reconnect" requirement). `now_ms` in the reply is how the client computes clock skew (`useEpisode.ts:72`).

**`handle_in("vote", ...)` delegating to the episode process.** Reply-style handling is the documented request/response idiom: `{:reply, {:ok, response}, socket}` (`server/deps/phoenix/lib/phoenix/channel.ex:101-110,164-167`). The client's `castVote` pushes `vote` with `{option_idx}` and consumes an ok-reply `{tallies, your_vote}` (`useEpisode.ts:87-95`). The channel should stay a thin translator: `EpisodeServer.vote(episode, anon_id, idx)` via `GenServer.call`, then reply.

**One process per live episode** (MEDIUM — standard OTP idiom, corroborated by `server/AGENTS.md:60`): DynamicSupervisor + Registry, both named in child specs (`{DynamicSupervisor, name: Whn.EpisodeSupervisor}`, `{Registry, keys: :unique, name: Whn.EpisodeRegistry}`), episode processes registered `{:via, Registry, {Whn.EpisodeRegistry, episode_id}}`. AGENTS.md:60 documents the named-child-spec requirement explicitly. Nothing of this exists yet (grep of `server/lib` for DynamicSupervisor/Registry/Task.Supervisor: zero hits).

**Timeline ticks and clocks** (MEDIUM — standard idiom): `Process.send_after(self(), tick_msg, ms)` inside the EpisodeServer; every transition (vote open at ~10s, lock at ~20s, scene boundary) is a self-message. The wire protocol already assumes server-owned time: `Playback.started_at_ms` (`types.ts:13`), `VoteState.deadline_ms` (`types.ts:20`), `EpisodeSync.now_ms`. The server broadcasts absolute epoch-ms; clients render countdowns from `deadline_ms + skewMs`. Broadcast from the GenServer with `WhnWeb.Endpoint.broadcast("episode:live", event, payload)` or `Phoenix.PubSub.broadcast(Whn.PubSub, ...)` — the endpoint-broadcast form is documented at `channel.ex:77-80`.

### Vote aggregation idioms

- State shape (MEDIUM idiom): `votes :: %{anon_id => option_idx}`; tallies derived (`Enum.frequencies_by`) — dedupe is free, revote is a map put (policy decision: allow revote until lock or first-write-wins; README.md:385-387 leaves "voting policy" to the episode process).
- Wire contract fixes tallies as `number[]` aligned to options (`types.ts:16-24`); `vote_update` carries only `{tallies}` (`useEpisode.ts:49-51`); `vote_locked` carries `{winner_idx, tallies}` (`useEpisode.ts:52-65`); `vote_closed` clears the overlay (`useEpisode.ts:66`).
- Broadcast throttling: no local precedent. The client is agnostic (it just renders the latest `vote_update`), so per-vote immediate broadcast vs a 200-300ms `Process.send_after` batch tick is purely a server choice (LOW — interval speculative; the batching mechanism itself is the same send_after idiom as timeline ticks).
- Deadline enforcement server-side: votes arriving after lock get `{:reply, {:error, %{reason: "locked"}}, socket}` — the error-reply form at `channel.ex:107-110`. The client countdown is display-only.
- Tie-breaking: no precedent in repo, brief, or README (README.md:415-426 open decisions don't cover it). Open question.

### Ecto fire-and-forget persistence

- `server/AGENTS.md:100-109` (HIGH, in-repo rules): programmatic fields like `user_id`/`anon_id` are never in `cast` lists; migrations via `mix ecto.gen.migration`; `:string` type even for text columns.
- Keeping the hot loop non-blocking (MEDIUM idiom): a named `{Task.Supervisor, name: Whn.TaskSupervisor}` child; `Task.Supervisor.start_child(Whn.TaskSupervisor, fn -> Repo.insert(...) end)` for fire-and-forget writes from `handle_info`/`handle_cast` — the EpisodeServer never waits on Postgres in its tick path. Synchronous `Repo` calls are acceptable only at episode boundaries (create/finalize). AGENTS.md:61 nudges toward supervised-task idioms generally.
- Vote uniqueness: unique index on `(decision_id, anon_id)` (brief requirement) + `Repo.insert(..., on_conflict: :nothing)` or `on_conflict: {:replace, [:option_idx]}` depending on revote policy (MEDIUM idiom). The GenServer map is the runtime authority; the table is the durable record — no double bookkeeping in the hot path.
- jsonb: `field :options, {:array, :string}` / `field :story_state, :map` map to jsonb under postgrex (MEDIUM idiom). Story-state snapshots per beat match README.md:339-354 persistence list.
- Test shape constraint (HIGH, `server/AGENTS.md:71-78`): `start_supervised!/1` for EpisodeServer tests, no `Process.sleep`, use `:sys.get_state/1` to synchronize — this materially shapes how testable the tick design is (prefer explicit tick messages you can send manually over opaque timers).

### fal pipeline / HTTP-client patterns

- **Req is mandated, not installed.** `server/AGENTS.md:6` — "Use the already included and available `:req`... avoid `:httpoison`, `:tesla`, and `:httpc`" — but `server/mix.exs:40-52` has no `:req` and mix.lock confirms. Must be added; the AGENTS.md claim of "already included" is boilerplate drift (near-miss).
- fal contract as practiced in this repo (HIGH — read from reference source):
  - Endpoints: `minimax/h3-max/text-to-video`, `minimax/h3-max/image-to-video`, vision via `openrouter/router/vision` + `google/gemini-2.5-flash-lite` (`tmp/interdimensional-game/lib/fal.ts:10-14`).
  - i2v input: `{prompt, image_url, duration, resolution: "480P", seed, prompt_expansion_mode: "disabled"}`; response `data.video.url` (`fal.ts:43-58`, `experiments/_lib.mjs:42-56`).
  - `prompt_expansion_mode`: `"balanced"` only on a t2v cold start, `"disabled"` whenever chaining from a frame so "the shot grammar stays ours" (`fal.ts:45`).
  - Seed discipline: fixed per run, `seed + beat` per shot so near-identical prompts stop producing near-identical clips (`fal.ts:26-29,44`).
  - `fal.storage.upload` exists for large binary inputs (`_lib.mjs:99`) — relevant if data-URI `image_url` proves too large.
- The reference always goes through `@fal-ai/client` `fal.subscribe` (`fal.ts:55`) or the Next server proxy (`app/api/fal/proxy/route.ts:1-4`); the repo contains **no** direct `queue.fal.run` REST usage. The submit → status-poll → response flow with `Authorization: Key <FAL_KEY>` is training knowledge here (MEDIUM) — exact REST shapes belong to the external researcher.
- Supervised generation tasks reporting back (MEDIUM idiom, mirroring the reference's structure): the JS version guards every async continuation with a run token and beat check (`lib/engine.ts:94-99,169,229-236,310-311`). The Elixir analog: `Task.Supervisor.async_nolink` from the EpisodeServer, results arriving as `handle_info({ref, result})` / `{:DOWN, ...}` — a crashed generation task sends DOWN instead of killing the episode, and a beat tag in the message replicates the stale-guard.
- Pipeline overlap: the reference's core trick is "the choice phase *is* the generation window" — 3 branches pre-film in parallel while the player decides (`engine.ts:474-509`, `tmp/interdimensional-game/README.md` "Branch pre-generation"). Ours is winner-only (brief), so the overlap shifts to the brief's timing model: bridge generates during the remaining 10s of scene, next scene's first segment during bridge playback (README.md:87-99).
- Cost runaway guard worth porting: `engine.ts:104-109` — "an unattended tab must never generate video forever" (max 2 auto-advances, then hold). Live analog: stop the generation loop on zero presence or episode end.

### ffmpeg last-frame extraction

- Repo pattern (HIGH): `experiments/grab-frames.mjs:7-12` and `_lib.mjs:65-78` — `ffmpeg -y -sseof -0.25 -i <file> -frames:v 1 -q:v 3 out.jpg`, executed with `execFileSync(..., {stdio: "pipe"})`. Elixir analog: `System.cmd("ffmpeg", [...], stderr_to_stdout: true)` against a tmp-dir download. Note the repo uses `-sseof -0.25`, not `-0.5`.
- Data-URI feed: `_lib.mjs:107-110` builds `data:image/jpeg;base64,...` from a frame file; `fal.ts:39-52` passes such a data URI directly as `image_url`. The client-side canvas variant (`lib/frames.ts:44-90`) grabs the last frame at `duration - 0.05` at quality 0.92.
- **Do not imitate the media proxy.** `app/api/media/route.ts:3-4` exists solely because browser canvas grabs need same-origin video. Server-side ffmpeg removes that need entirely, so clients keep direct fal CDN URLs — which the brief mandates anyway (backend never proxies video bytes).
- ffmpeg is in the devshell (`flake.nix:33`), so `System.cmd("ffmpeg", ...)` needs no vendoring.

### React patterns from the reference (keep / adapt / reject)

- **Store shape.** Reference: one mutable `GameDirector` class publishing immutable snapshots through `useSyncExternalStore` (`engine.ts:120-130`, `app/page.tsx:14-18`). Drafted hook: 8 `useState` slots updated by discrete channel events (`web/src/lib/useEpisode.ts:22-30`). Tradeoff, not verdict: the server owns the state machine here, so the client is a projection and per-event `useState` works; but three separate handlers mutate the same `vote` object (`useEpisode.ts:48-66,90-94`) and join-sync sets five slots at once (`useEpisode.ts:70-77`) — a `useReducer` keyed by protocol event would make "one event, one transition" explicit and keep sync/update ordering atomic. The Director-class pattern itself is over-shaped for a client that holds no authority.
- **Stale-async guards.** Token + beat checks on every continuation (`engine.ts:12-16` states the invariant; enforced at `engine.ts:169,236,311,336,690`). Client analog is smaller but real: `vote_update` arriving after `vote_closed` must not resurrect the overlay — the drafted functional `setVote((v) => v ? ... : v)` null-guards (`useEpisode.ts:50,56`) already implement this.
- **Dual player.** The reference does *not* implement active/standby — it uses one `<video key={url}>` plus a freeze-frame `<img>` of the last frame to hide every seam "behind a diegetic pause instead of a spinner" (`components/stage.tsx:8-49`). README §9 requires the real activePlayer/standbyPlayer pair (README.md:290-299); the protocol supports it (`preload` event, `useEpisode.ts:47`; per-10s-segment URL list, `types.ts:11`). The freeze-frame-as-poster trick is worth keeping as the swap/gap mask.
- **Mobile autoplay.** Reference video is `autoPlay playsInline` but **not muted** (`stage.tsx:33-40`) — fine for its desktop game, fatal on mobile where unmuted autoplay is blocked (MEDIUM — well-known browser policy, unverified here). Ours needs `muted` + `playsInline` + a tap-to-unmute affordance. `web/index.html:6-7` already ships the right viewport (`maximum-scale=1, viewport-fit=cover` — cover matters for TikTok-style edge-to-edge chrome behind notches).
- **Countdown.** `ChoiceTimer` (`components/hud.tsx:76-113`): rAF loop updating `now`, deriving width-% and seconds from `deadline - now`, urgency class under threshold. Direct adaptation: `deadline_ms - (Date.now() + skewMs)`.
- **Clip-end handling.** Reference advances state from the client's `onEnded` (`stage.tsx:39`, `engine.ts:341-350`) because the client is authoritative. Reject for live: `started_at_ms` + segment math makes the server clock authoritative; `onEnded` degrades to a local swap trigger at most.

### CSS/component conventions (reference anatomy)

- Structure: flat `components/*.tsx` (stage, hud, choices, overlays, screens), single plain-CSS `app/globals.css` (832 lines) with CSS-variable palette (`globals.css:2-15`) and `/* ---------- section ---------- */` comments. No Tailwind, no CSS modules.
- Full-bleed stage: `.theater { position: fixed; inset: 0 }`, video `object-fit: contain` (`globals.css:244-259`). Vertical 9:16 wants `cover` instead.
- Overlay scrims, not panels: top HUD under a `linear-gradient(rgba(0,0,0,.72), transparent)` (`globals.css:280-290`), lower-third under `linear-gradient(transparent, rgba(0,0,0,.82) 45%)` (`globals.css:423-434`), plus a radial `.vignette` (`globals.css:270-276`). This is exactly the TikTok top-badge/bottom-caption chrome convention.
- **Frosted glass does not exist here**: zero `backdrop-filter` occurrences in globals.css. Option pills use solid `rgba(10,10,12,.86)` cards (`globals.css:484-493`). The Instagram frosted card is net-new CSS (MEDIUM — `backdrop-filter: blur()` is standard, but there is no local precedent to copy).
- **Percentage-bar mechanic exists twice** and is the Instagram poll-bar pattern: `hp-fill` width-% with state-based color classes (`components/hud.tsx:16-28`, `globals.css:316-329`) and `timer-fill` width-% with `.urgent` (`hud.tsx:100-106`). Add a CSS `transition: width` and it is the animated vote bar; the checkmark-on-your-pick and pill-to-bar morph are new.
- Keyed re-mount for re-triggering CSS animation: `key={beat-...}` on freeze/hit-flash elements (`stage.tsx:44`, `hud.tsx:36`).

### Don't Hand-Roll (local half)

| Instead of hand-rolling | Use | Evidence |
|---|---|---|
| Custom viewer counting over PubSub | `Phoenix.Presence` (+ JS `Presence` class, already used) | `deps/phoenix/lib/phoenix/presence.ex:24-65`; `useEpisode.ts:39-40` |
| Pid maps / process dictionaries for episode lookup | `Registry` via-tuples + named `DynamicSupervisor` | `server/AGENTS.md:60` |
| `:httpc`/hand-rolled HTTP for fal | `Req` (must be added to deps first) | `server/AGENTS.md:6`; absent from `server/mix.exs:40-52` |
| Raw WebSocket client | `phoenix` npm client (already a dep and in use) | `web/package.json` (`phoenix ^1.7.21`); `useEpisode.ts:2` |
| Raw `spawn`/unsupervised Task for generation | named `Task.Supervisor`, results as messages | `server/AGENTS.md:61` + stale-guard precedent `engine.ts:94-99` |
| Manual per-socket send loops | `Endpoint.broadcast` / PubSub fan-out | `deps/phoenix/lib/phoenix/channel.ex:77-88` |
| Client clocks for countdown | server `deadline_ms`/`now_ms` skew already in protocol | `types.ts:13,20,30`; `useEpisode.ts:72` |

### Common Pitfalls (local near-misses)

- **Port mismatches will break first run:** `web/vite.config.ts:6` targets `127.0.0.1:57400` ("keep in sync with server/config/dev.exs") but `server/config/dev.exs:22` sets no port (Phoenix default 4000); `dev.exs:4-11` points at Postgres on default 5432 with `postgres/postgres`, while the flake runs Postgres on 57432 (`flake.nix:14,21`).
- **AGENTS.md/deps drift:** `:req` mandated (`AGENTS.md:6`) but not in `mix.exs` — an implementer following AGENTS.md will hit a compile error until it's added.
- **Unmuted autoplay** in the reference (`stage.tsx:33-40`) silently fails on mobile; the whole product is mobile-first.
- **Stale async clobbering** is the reference's most-documented foot-gun — the engine header comment exists because of it (`engine.ts:12-16`), and there's an explicit in-code warning about TypeScript narrowing going stale across awaits (`engine.ts:688-690`). The Elixir side gets this ~free (messages serialize through the GenServer) but generation-task results still need beat tags.
- **LLM JSON is never trusted raw:** brace-slice extraction (`fal.ts:112-118`), field-by-field coercion with caps (`adjudicator.ts:62-79`), and a `fallbackVerdict` on parse failure (`engine.ts:325`). Celeris parsing should follow the same lenient-parse + fallback shape; "Celeris failure: retry structured generation without reopening vote" is a stated requirement (README.md:377-379).
- **Final-frame hygiene:** prompts must end "readable" because the last frame seeds the next shot (`adjudicator.ts:40`) — a video_prompt authoring rule for Celeris, not just a model nicety.
- **Runaway generation cost:** `engine.ts:104-109` guard + README cost note ("dying is the cheapest way to stop"). The live analog (stop generating on zero viewers / episode end) has no guard yet anywhere.

## Open questions

- Tie-breaking at vote lock — no precedent in repo, brief, or README §14. Planner decision.
- `vote_update` cadence: immediate per-vote vs 200-300ms batch tick — client is agnostic; depends on target concurrency, which is itself README open decision #5.
- Exact `queue.fal.run` REST shapes (submit/status/response paths, webhook option, polling interval etiquette) — outside this focus; repo only ever uses `@fal-ai/client`. For the external researcher.
- Whether MiniMax H3 Max's `image_url` accepts large base64 data URIs from Elixir REST calls, or whether frames should go through fal storage upload (`_lib.mjs:99` precedent) — external.
- Topic naming: client hardcodes `episode:live` (`useEpisode.ts:36`) while the OTP design keys episodes by id; either the channel maps `"live"` to the current episode or the client learns real ids. Planner call.
- Audio UX given mandatory muted autoplay (tap-to-unmute placement) — product question, no precedent.

## Sources

### Primary (HIGH confidence)
- `server/lib/whn/application.ex`, `server/lib/whn_web.ex`, `server/lib/whn_web/endpoint.ex`, `server/config/dev.exs`, `server/mix.exs`, `server/mix.lock`, `server/AGENTS.md` — read directly; current scaffold state and in-repo rules.
- `server/deps/phoenix/lib/phoenix/presence.ex`, `.../channel.ex`, `.../socket.ex` — official Phoenix 1.8.13 docs, vendored in-repo and read directly.
- `web/src/lib/useEpisode.ts`, `types.ts`, `identity.ts`, `web/vite.config.ts`, `web/index.html`, `web/package.json` — drafted client protocol, read directly.
- `tmp/interdimensional-game/lib/{engine,fal,frames,adjudicator}.ts`, `components/{stage,hud,choices}.tsx`, `app/page.tsx`, `app/globals.css`, `app/api/{media,fal/proxy}/route.ts`, `experiments/{grab-frames.mjs,_lib.mjs}`, its `README.md` — reference implementation, read directly.
- `README.md` (product/tech brief), `flake.nix` — read directly.
- `~/.claude/skills/react-best-practices/SKILL.md` — read; general perf rules (derived-state subscriptions, explicit conditional rendering) apply but contains nothing specific to this sprint's realtime patterns.

### Secondary (MEDIUM confidence)
- OTP idioms not yet present in repo but corroborated by `server/AGENTS.md:60-61`: DynamicSupervisor + Registry via-tuples, named Task.Supervisor, `Task.Supervisor.async_nolink` + `handle_info({ref,...}/{:DOWN,...})`, `Process.send_after` tick loops. Well-established Elixir/Phoenix practice from training, consistent with in-repo guidance.
- Vote state as `%{anon_id => idx}` with derived tallies; `on_conflict` upsert against a `(decision_id, anon_id)` unique index — standard Ecto/OTP idioms, no in-repo instance yet.
- Mobile autoplay requires `muted` + `playsInline` — long-standing iOS/Android WebKit/Chrome policy from training; not re-verified against current platform docs.
- fal queue REST flow (submit → status poll → response, `Authorization: Key`) — training knowledge; repo never exercises it directly.

### Tertiary (LOW confidence)
- 200-300ms as the "right" vote-broadcast batch interval — plausible, no source; validate against target concurrency.
- `backdrop-filter: blur` performance on low-end mobile over live video — inferred concern, unmeasured; validate during UI work.

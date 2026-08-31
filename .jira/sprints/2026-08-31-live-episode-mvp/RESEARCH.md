# Research: 2026-08-31-live-episode-mvp

**Date**: 2026-08-31
**Domain**: realtime backend (Elixir/Phoenix) + generation pipeline (fal) + frontend/mobile-ui (React)
**Confidence**: HIGH (contracts and conventions) / MEDIUM (generation latency timing model)
**Valid until**: 2026-09-30 — stacks are stable; exception: H3 Max promo pricing ends 2026-09-01 (cost figures below double)

## Summary

Three focus areas converge on one picture. The reference impl (`tmp/interdimensional-game`) proves the entire generation pipeline — fal endpoints, param contracts, frame chaining, LLM-JSON discipline — but runs it all in the browser for a single player. The multi-user version inverts every authority: generation, seeds, timers, and playback clocks move into a Phoenix `EpisodeServer`; clients become projections of server state. Branch pre-generation (the reference's core trick) is explicitly replaced by the brief's winner-only pipeline, whose latency budget is "remaining scene + bridge playback".

The wire protocol is already fixed by the committed web drafts (`web/src/lib/types.ts`, `useEpisode.ts`): topic `episode:live`; join reply `EpisodeSync {phase, episode, now_ms, playback, vote}`; broadcasts `phase`, `playback`, `preload`, `vote_open`, `vote_update`, `vote_locked`, `vote_closed`; push `vote {option_idx}` → `{tallies, your_vote}`. The server conforms to this contract. All external facts the plan depends on were verified: H3 Max t2v supports `aspect_ratio: "9:16"` (enum verbatim from OpenAPI), resolution is `480P|768P` only, duration integer 5–15; i2v derives aspect from `image_url`, so the FLUX-vertical-frame → i2v chain controls aspect end-to-end. fal's queue HTTP API (submit/status/result/cancel + webhook param) is documented and small. The user-mandated `fal_ex` hex package (0.1.0, Tesla-based) covers the full needed surface but is 14 months dormant — wrap it thin so a Req fallback stays a one-file swap.

The one soft spot: **real H3 Max wall-clock latency at 480P/10s is undocumented**. The reference's measured ~6–8s comment is the only number in hand; the README §2 timing model rests on it. Plan an early empirical spike. Also material: iOS Safari ignores `preload="auto"`, so the dual-player preload needs the `#t=0.001`/warm-play workaround; mobile autoplay requires `muted playsinline` + tap-to-unmute.

**Primary recommendation:** Build server-out from the client-drafted protocol: EpisodeServer (GenServer, `Process.send_after` ticks, server-owned epoch-ms clocks) under Registry + DynamicSupervisor, Presence for viewers, `Task.Supervisor.async_nolink` for generation with beat-tagged results, `fal_ex` behind a `Whn.Fal` wrapper, local ffmpeg (flake) for last frames, Ecto fire-and-forget persistence — and fix the three port mismatches before anything else runs.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| fal generation calls + FAL_KEY | API/Backend (Phoenix pipeline) | — | Key server-side (brief); one canonical clip per beat |
| Last-frame extraction | API/Backend (ffmpeg via flake) | Infra (hosted fal extract-frame as alt) | Browser canvas approach dies with multi-user |
| Script engine (Celeris §5 contract) | API/Backend | — | Story state is server truth; votes mutate it |
| Vote window, deadline, lock | API/Backend (EpisodeServer) | Browser (display-only countdown) | Server-synchronized 10s window is a brief constraint |
| Vote counting, one-per-anon-id | API/Backend (EpisodeServer + channel) | Database (unique index backstop) | Runtime authority in GenServer map; durable in Postgres |
| Playback clock | API/Backend (`started_at_ms` broadcast) | Browser (skew-corrected rendering) | Late joiners/reconnects seek from server time |
| Video bytes | CDN/Static (direct fal.media URLs) | — | Backend never proxies video (README §9) |
| Viewer count | API/Backend (Phoenix.Presence) | Browser (Presence JS) | Client hook already conformant |
| Persistence | Database/Storage (Postgres 57432) | — | README §11 tables; recovery flow deferred |
| Vertical video UI, poll overlay, countdown | Browser (React SPA) | — | TikTok/Instagram experience is pure client |

## Codebase

Full detail in `research-codebase.md`. Headlines:

- **Existing, load-bearing:** the reference fal contract (`tmp/interdimensional-game/lib/fal.ts:10-65`): t2v/i2v endpoints, `{prompt, duration, resolution "480P", seed: runSeed+beat, prompt_expansion_mode: "disabled"|"balanced", image_url | aspect_ratio}`, response `data.video.url`; vision route `openrouter/router/vision` + `google/gemini-2.5-flash-lite` (`fal.ts:13-14`); server-side ffmpeg last-frame recipe `ffmpeg -sseof -0.25 -i clip.mp4 -frames:v 1 -q:v 3` (`experiments/grab-frames.mjs:7-13`); the drafted wire protocol (`web/src/lib/types.ts:1-35`, `useEpisode.ts`); flake toolchain with Postgres on 57432 (`flake.nix:14,21,45`).
- **Would change:** `server/config/dev.exs` (add `port: 57432` to Repo — Postgrex ignores PGPORT; pin HTTP port 57400 to match `web/vite.config.ts:6`), `server/config/test.exs` (same Repo port), `server/lib/whn_web/endpoint.ex` (mount `socket "/socket"`), `server/lib/whn/application.ex:15-16` (insertion point for Presence/Registry/DynamicSupervisor/Task.Supervisor), `server/mix.exs` (add fal client dep — **no HTTP client present** despite `server/AGENTS.md:6` claiming `:req` is included), empty `server/priv/repo/migrations/`, missing `web/src/main.tsx` (index.html references it; no entrypoint/routes/components exist yet).
- **Reference-only:** `lib/engine.ts` (token/beat stale-async guards, verdict-during-playback overlap), `lib/adjudicator.ts` (LLM-JSON parse/clamp/fallback discipline, FINAL FRAME HYGIENE and SOUND_CLAUSE prompt rules), `components/hud.tsx` (rAF countdown, width-% bars), `app/api/media/route.ts` (dies; canvas-CORS only).
- Timing evidence: "480P/10s films in ~6-8s" (`lib/types.ts:5-7`, stated as measured) — the number the whole schedule leans on.

## Patterns & conventions

Full detail in `research-patterns.md`. Headlines:

- **To imitate (verified against vendored Phoenix 1.8.13 docs):** Presence module `use Phoenix.Presence, otp_app: :whn, pubsub_server: Whn.PubSub` at `lib/whn_web/channels/presence.ex`, supervised after PubSub before Endpoint, tracked in `:after_join` (`deps/phoenix/lib/phoenix/presence.ex:24-65`); join reply `{:ok, sync, socket}` as the reconnect story (`channel.ex:370-373`); vote as `{:reply, {:ok, %{tallies, your_vote}}, socket}` (`channel.ex:101-110`); episode processes as `{:via, Registry, ...}` under named DynamicSupervisor (`server/AGENTS.md:60`); `Process.send_after` self-ticks for the timeline; `Task.Supervisor.async_nolink` + beat-tagged `handle_info` results so a crashed generation never kills the episode; vote state `%{anon_id => option_idx}` with derived tallies; Ecto writes fire-and-forget via named Task.Supervisor, unique index `(decision_id, anon_id)` as durable backstop; test-shaped ticks (explicit tick messages, `start_supervised!`, no `Process.sleep` — `server/AGENTS.md:71-78`).
- **To imitate (reference impl):** seed-per-beat + `prompt_expansion_mode: "disabled"` when frame-chaining; lenient LLM-JSON brace-slice + field clamping + canned fallback (maps to README §12 "retry without reopening vote"); freeze-frame seam masking; rAF countdown from `deadline_ms + skewMs`; width-% bar with CSS `transition: width` as the Instagram poll bar seed.
- **To deliberately not imitate:** media byte proxy; unmuted `autoPlay` (`stage.tsx:33-40` — fatal on mobile); single-`<video>` element (README §9 wants active/standby pair); client-authoritative timers/`onEnded` state advancement.
- Frosted-glass (backdrop-filter) has zero local precedent — net-new CSS for the Instagram card.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---|---|---|---|
| fal_ex | 0.1.0 | fal queue/run/storage from Elixir | User-mandated; surface verified: run/subscribe/Queue.submit-status-result-cancel (+`webhook_url`), FAL_KEY config, Storage.upload, arbitrary model-id strings |
| phoenix (hex) | 1.8.13 | channels, Presence, PubSub | Already scaffolded |
| ecto_sql/postgrex | 3.14 / 0.22.4 | persistence, `port: 57432` support | Already scaffolded; `:port` documented |
| phoenix (npm) | 1.8.13 | Socket/Channel/Presence client | Matches server; ESM exports, Vite-safe (bump from drafted ^1.7.21) |
| TanStack Start | latest (^1.x) | web app framework (SPA mode) | User-mandated mid-research; scaffold `npx @tanstack/cli@latest create`; SPA mode via `tanstackStart({spa: {enabled: true}})` in vite config (prerendered `/_shell.html`, no SSR); supersedes the hand-rolled Vite + code-based-router scaffold — existing `src/lib/*` drafts carry over, `web/` gets re-bootstrapped |
| @tanstack/react-router | ^1.170 | routing (via Start, file-based) | Bundled by Start; React 19 peer-supported |

### Supporting

| Library | Version | Purpose | When to Use |
|---|---|---|---|
| @types/phoenix | 1.6.7 | client types | Lags 1.8; augment locally if newer Socket opts needed |
| ffmpeg (nix) | 9.0.1 | last-frame extraction | Default path; already in devshell |
| req | latest | HTTP fallback | Only if fal_ex disappoints (surface is 4 URLs + 1 header) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| fal_ex | thin Req wrapper | fal_ex is 14 months dormant (0.1.0, 6 commits, 0 stars); wrapper is trivial but user chose fal_ex — isolate behind `Whn.Fal` so the swap stays one file |
| local ffmpeg | fal-ai/ffmpeg-api/extract-frame (`frame_type: "last"`) | Hosted: no mp4 download, but an extra queue round-trip per segment on the critical path; local: zero queue latency, download cost only |
| polling queue status | `?fal_webhook=` on submit | Webhook needs a public URL (dev tunnels) — polling is right for dev; webhook is a prod optimization |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Viewer counting | custom PubSub counters | Phoenix.Presence (`deps/phoenix/lib/phoenix/presence.ex:24-65`; client already uses `Presence`) | conflict-free distributed tracking is solved |
| Episode process lookup | pid maps | Registry via-tuples + named DynamicSupervisor (`server/AGENTS.md:60`) | restart-safe addressing |
| fal HTTP | :httpc / hand-rolled | fal_ex (user-mandated), Req as named fallback | queue semantics, auth, storage handled |
| WebSocket client | raw WebSocket | phoenix npm client (already in use, `useEpisode.ts:2`) | heartbeats, rejoin, presence sync |
| Generation jobs | raw spawn | Task.Supervisor.async_nolink + beat-tagged handle_info | crash isolation; stale-guard precedent `engine.ts:94-99` |
| Countdown clocks | client Date.now() authority | server `deadline_ms`/`now_ms` skew (already in protocol, `types.ts:13,20,30`) | multi-viewer sync is the product |

**Key insight:** every hard realtime problem here already has a Phoenix primitive or an in-repo precedent; the genuinely new code is the EpisodeServer state machine, the Celeris prompt/contract, and the poll-overlay CSS.

## Common Pitfalls

### Port mismatches (will break first run)
- **What goes wrong:** Vite proxies to 57400; Phoenix defaults to 4000. Repo config points at Postgres 5432; flake runs 57432.
- **Why:** `dev.exs:22` sets no HTTP port; `dev.exs:4-11`/`test.exs:8-14` set no Repo port; Postgrex does not read PGPORT.
- **How to avoid:** pin `http: [port: 57400]` and `port: 57432` in dev.exs/test.exs first task.
- **Warning signs:** `connection refused` on /socket proxy; `Postgrex.Error connection refused` on ecto.create.

### AGENTS.md/deps drift
- **What goes wrong:** `server/AGENTS.md:6` says `:req` is "already included"; mix.exs has no HTTP client at all.
- **How to avoid:** add the fal client dep explicitly; treat AGENTS.md stack claims as unverified boilerplate.

### Undocumented H3 Max latency (timing model risk)
- **What goes wrong:** README §2's whole schedule (bridge in ≤10s of remaining scene; next segment during bridge) rests on ~6-8s per 480P/10s clip — a reference-impl comment, not a doc.
- **How to avoid:** empirical spike early (one t2v + one i2v timed round-trip incl. download+ffmpeg); design the `hold` phase as a first-class state, not an error.
- **Warning signs:** `timings` field in fal responses trending above ~8s; bridge ending before next scene's segment 0 lands.

### Mobile autoplay + preload
- **What goes wrong:** unmuted autoplay silently blocked (iOS + Chrome Android); iOS Safari ignores `preload="auto"` so the standby player fetches nothing until play.
- **How to avoid:** `muted playsinline` + tap-to-start/unmute gate; warm the standby with `#t=0.001` URL fragment or muted play()/pause().
- **Warning signs:** black frame at swap on iPhone; `NotAllowedError` from `video.play()`.

### LLM JSON trusted raw
- **What goes wrong:** Celeris output parsed naively stalls the episode on the first malformed reply.
- **How to avoid:** port the reference discipline — brace-slice extraction, per-field clamp, canned fallback, retry without reopening the vote (README §12; `adjudicator.ts:62-88,219-252`).
- **Warning signs:** episode stuck in post-lock generation with a JSON parse error in logs.

### Final-frame hygiene + sound clause (prompt authoring)
- **What goes wrong:** shots ending in close-up/blur seed unusable next frames; H3 Max invents pseudo-language dialogue.
- **How to avoid:** Celeris system prompt carries the reference's FINAL FRAME HYGIENE rule (`adjudicator.ts:40`) and SOUND_CLAUSE (`worlds.ts:220-221`); vertical camera/style tokens appended to every video_prompt.

### Runaway generation cost
- **What goes wrong:** an episode loop generating forever with zero viewers; at post-promo pricing each scene+bridge cycle ≈ $2.00.
- **How to avoid:** stop the loop on zero presence or episode end (reference guard precedent `engine.ts:104-109`).
- **Warning signs:** fal dashboard spend with no presence entries.

## SOTA Updates

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| phoenix npm ^1.7.21 (drafted) | 1.8.13 (matches server) | 2026-08-25 | bump package.json; wire-compatible either way |
| H3 Max promo pricing ($0.025/s 480P) | $0.05/s from Sept 1, 2026 | tomorrow | cost math: $0.50/segment, ≈$2.00/cycle |

## Risks & unknowns

- **Generation wall-clock** — undocumented; resolves via timed spike (also validates FLUX 720x1280 custom size and whether i2v `image_url` accepts data URIs vs needing `FalEx.Storage.upload`).
- **fal_ex dormancy** — 0.1.0, no pushes since Jun 2025; resolves by wrapping in `Whn.Fal` with Req fallback documented.
- **Text-only calls on `openrouter/router/vision`** — schema-valid, behavior unverified; resolves in the same spike (or always attach the latest frame, which grounds the script anyway).
- **Vote policy details** — tie-breaking and revote-until-lock vs first-write-wins have no precedent anywhere; planner decision (D-XX candidates).
- **Topic naming** — client hardcodes `episode:live`; server keys episodes by id. Channel can map "live" → current episode, or client learns ids. Planner decision.
- **`vote_update` cadence** — per-vote vs 200-300ms batch; client agnostic; planner decision.

## Open questions for planner

- Tie-breaking rule at vote lock (first-reached max? random among max? lowest index?).
- Revote until lock (Instagram-poll behavior is one tap, immutable) vs allow changing — affects channel reply and unique-index conflict strategy.
- `vote_update` broadcast cadence at MVP concurrency.
- `episode:live` topic → episode-id mapping strategy.
- Celeris model id on `openrouter/router` vs `/vision` (reference precedent: `google/gemini-2.5-flash-lite`).
- Local ffmpeg vs hosted extract-frame for the critical path.
- Bridge-late behavior: hold on last bridge frame (freeze-frame mask) — confirm as the §12 "narrative-safe hold state".
- Bump web `phoenix` to 1.8.13 now or ship on 1.7.24.
- TanStack Start re-bootstrap mechanics: scaffold fresh and port `src/lib/*` + vite proxy + index meta into it, or graft Start onto the existing `web/` — fresh scaffold recommended (user: "it comes with everything we need"); keep SPA mode on, ignore server functions (Phoenix owns the backend).
- PORT wiring: pin 57400 in dev.exs vs export in flake shellHook (or both).

## Sources

### Primary (HIGH confidence)
- Per-focus files, all claims cited inline: `research-codebase.md` (repo files with path:line), `research-patterns.md` (repo + vendored Phoenix 1.8.13 hexdocs), `research-external.md` (20 fetched official pages: fal queue docs, H3 Max t2v/i2v /api + OpenAPI JSON, openrouter router/vision, flux-2-pro, ffmpeg-api/extract-frame, fal_ex hexdocs + hex.pm + GitHub API, npm registry, TanStack code-based routing docs, Phoenix.Presence/Endpoint hexdocs, ecto_sql hexdocs, WebKit + Chrome autoplay policies).

### Secondary (MEDIUM confidence)
- fal webhook signature header (doc page 429'd); H3 Max 768P pixel dims; ffmpeg-api pricing; data-URI acceptance on vision `image_urls`; iOS `preload="auto"` ignored + `#t=0.001` workaround (multiple agreeing community sources); OTP idioms corroborated by AGENTS.md but not yet instantiated in repo; ~6-8s generation latency (reference comment, not re-measured).

### Tertiary (LOW confidence)
- npm phoenix 1.7 client ↔ 1.8 server wire compatibility (memory); 200-300ms batch interval; backdrop-filter perf on low-end mobile over video.

## Metadata

**Research scope:**
- Focus areas covered: codebase, patterns, external
- Omitted sections: none

**Confidence breakdown:**
- Codebase findings: HIGH — read directly, path:line cited
- Patterns & conventions: HIGH for Phoenix conventions (vendored docs) / MEDIUM for OTP idioms not yet in repo
- Standard stack: HIGH — registries and docs fetched; fal_ex maturity quantified
- Pitfalls: HIGH for ports/deps/autoplay (verified), MEDIUM for latency/preload specifics

**Valid-until reasoning:** 2026-09-30 — Phoenix/TanStack/fal APIs stable on ~monthly horizons; pricing table changes 2026-09-01 (noted inline); re-verify H3 Max schema if fal versions the endpoint.

---

*Sprint: 2026-08-31-live-episode-mvp*
*Research completed: 2026-08-31*
*Next step: `/jira:plan`*

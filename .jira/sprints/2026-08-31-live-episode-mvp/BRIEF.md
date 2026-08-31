# Brief: 2026-08-31-live-episode-mvp

**Created:** 2026-08-31
**Source:** user-prompt
**Issue:** none

## Statement

MVP loop for the realtime audience-controlled story platform (README.md brief + PLOT.md launch property): one live episode where video plays, audience votes on the next beat, winner generates the continuation.

Confirmed decisions from the session:

- Phoenix backend per spec: channels, presence, one supervised EpisodeServer per episode, vote aggregation with one-vote-per-anon-id.
- Postgres via nix flake on port 57432; Ecto persistence for episodes/beats/decisions/votes.
- Web client bootstrapped with TanStack Start in SPA mode (React + TanStack Router on Vite; NOT Next.js) with phoenix js channels. User: "use tanstack start to bootstrap the web. it comes with everything we need."
- Mobile-first vertical TikTok-style dual-player video stage with direct fal CDN preload.
- Instagram-story-poll style vote overlay with live percentage bars and a 10-second vote window/countdown.
- Generation pipeline per brief: Celeris-shaped script engine (implemented against fal's LLM router, README §5 JSON contract) → fal MiniMax H3 Max bridge (i2v 480P vertical) → ffmpeg last-frame extract → next 30s scene as 3 chained 10s segments. Winner-only generation.
- Seed episode: Lagos Wahala "Salary Just Entered" (PLOT.md).

Reference implementation: `tmp/interdimensional-game` — a Next.js single-player version of the same fal pipeline (fal client, frame chaining, vision-LLM adjudicator, branch pre-generation).

Scaffolds already committed: `flake.nix` (elixir/node/ffmpeg/postgres@57432), `server/` (phx.new, channels-only), `web/` (vite + tanstack router + phoenix client; protocol types and useEpisode hook drafted).

Tracks for issues:

1. Phoenix episode core: EpisodeServer state machine, channel protocol, presence, voting.
2. Postgres persistence.
3. fal generation pipeline in Elixir: fal queue client, celeris, frames, pipeline orchestration.
4. Web TikTok/Instagram-vote experience.
5. DevX wiring: pg scripts, env, run instructions.

## Constraints

- Backend never proxies video bytes to clients — clients preload direct fal CDN URLs (README §9).
- One vote per anonymous identity per decision; rejected options never become story truth.
- Timing model per README §2: 30s scene, vote opens ~10s in, 10s window, lock at ~20s; bridge (10–12s) generates while the remaining scene plays; next scene's first segment generates while the bridge plays.
- Voting window is 10 seconds — the countdown must be server-synchronized.
- FAL_KEY stays server-side.
- Frontend framework is TanStack Start (SPA mode), not Next.js.

## Out of scope

- Accounts/OAuth (anonymous identity only), device fingerprinting.
- Comments, share cards, episode scheduling/cadence (5/day), replay mode.
- Redis, CDN infrastructure, horizontal scaling.
- Speculative generation of all vote branches (winner-only per brief §3).
- Backend-restart timeline reconstruction (persist, but recovery flow deferred).

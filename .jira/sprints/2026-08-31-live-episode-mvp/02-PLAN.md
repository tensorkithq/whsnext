---
sprint: 2026-08-31-live-episode-mvp
plan: II
wave: I
goal: One live episode runs the full loop — a vertical scene plays, the audience votes in a server-synced 10s window, and the locked winner generates the bridge and next scene via fal — proven by passing server test suites, a timed fal spike log, migrated Postgres tables, and a production build of the web client.
worktree: false
branch: jira/2026-08-31-live-episode-mvp
issue: none
depends_on: []
parallel_with: [I]
files_modified:
  - web/** (entire workspace re-bootstrap — no other plan touches web/)
covers:
  - D-07
  - D-08
  - D-10
  - "RESEARCH: mobile autoplay pitfall (muted+playsinline+tap gate), iOS preload workaround (#t=0.001), rAF countdown + width-% bar patterns, freeze-frame seam masking, frosted-glass is net-new CSS"
  - "GOAL: video plays / audience votes (client experience)"
effects:
  - WEB-01
  - WEB-02
  - WEB-03
  - WEB-04
  - WEB-05
---

# Plan II: Web — TanStack Start re-bootstrap + TikTok stage + Instagram poll

**Sprint goal:** One live episode runs the full loop — scene plays, audience votes in a server-synced 10s window, winner generates the continuation via fal — proven by tests, a spike log, migrations, and a web build.
**This plan delivers:** Track 4. `web/` reborn as a TanStack Start SPA carrying the frozen protocol drafts, a mobile-first dual-player vertical stage, and the Instagram-story poll overlay with a server-synced countdown.

Needs no running server: everything verifies through `npm run build`, `npm run typecheck`, and source inspection. The `react-best-practices` skill applies: no barrel imports, derive state instead of syncing it with effects, keep re-renders local to the overlay.

## Tasks

### I. Re-bootstrap web/ as TanStack Start (SPA mode)

- **Files:** `web/package.json`, `web/package-lock.json`, `web/vite.config.ts`, `web/tsconfig.json`, `web/index.html`, `web/src/routes/__root.tsx`, `web/src/routes/index.tsx`, `web/src/router.tsx` (or scaffold equivalents), preserving `web/src/lib/{types,identity,useEpisode}.ts`
- **Read first:** `web/src/lib/types.ts`, `web/src/lib/useEpisode.ts`, `web/vite.config.ts`, `web/index.html`, `web/package.json`
- **Action:** Per D-10: scaffold a fresh TanStack Start app (`npx @tanstack/cli@latest create`, React, no extras) into a temp dir, then replace `web/`'s scaffolding with it. Port forward verbatim: `src/lib/types.ts`, `src/lib/identity.ts`, `src/lib/useEpisode.ts`; the `index.html` title "Lagos Wahala — Live" and viewport meta (`maximum-scale=1, viewport-fit=cover`). Vite config must contain `tanstackStart({ spa: { enabled: true } })` and the dev proxy `{"/socket": {target: "http://127.0.0.1:57400", ws: true}, "/api": {target: "http://127.0.0.1:57400"}}` with `host: true`. Per D-08 pin `"phoenix": "1.8.13"` and keep `@types/phoenix ^1.6.7`. No Start server functions/routes — Phoenix owns the backend. Keep the `@` → `./src` alias. Root route renders the episode page (task II/III components).
- **Done when:** `(cd web && npm install && npm run build)` exits 0; `grep -E 'spa.*enabled|enabled.*true' web/vite.config.ts` matches; `grep '"phoenix": "1.8.13"' web/package.json` matches; `grep 'ws: true' web/vite.config.ts` matches (WEB-01); `web/src/lib/types.ts` is byte-identical to the pre-existing draft.
- **Covers:** D-08, D-10

### II. Vertical dual-player stage

- **Files:** `web/src/components/stage.tsx`, `web/src/styles.css` (stage section)
- **Read first:** `web/src/lib/useEpisode.ts` (store shape: `playback`, `preload`, `phase`, `skewMs`), `web/src/lib/types.ts` (`SEGMENT_SECONDS`, `started_at_ms`), `tmp/interdimensional-game/components/stage.tsx` (freeze-frame seam mask — imitate), RESEARCH.md "Mobile autoplay + preload" pitfall
- **Action:** Full-bleed fixed stage (`position: fixed; inset: 0`), video `object-fit: cover` for 9:16. Two `<video>` elements — active and standby — both `muted playsInline`, no `controls`. A tap-to-start gate overlay: first tap calls `.play()` on the active player and unmutes (store gate state; until tapped nothing plays). Segment scheduling from server truth per WEB-05: `elapsed = Date.now() + skewMs - playback.started_at_ms`; active segment index = `Math.floor(elapsed / (SEGMENT_SECONDS * 1000))` clamped to `segments.length - 1`; seek active player to the intra-segment offset on mount/playback change. Standby warming per WEB-03: when `preload` URLs arrive (or the next segment is known), set standby `src` to `url + "#t=0.001"` and run a muted `play().then(pause)` warm; swap active/standby at segment boundaries (local `onEnded` may trigger the swap, but never advances protocol state). Per D-07, when `phase === "hold"`: pause on the final frame and render a shimmer overlay (CSS gradient animation) — no spinner. Plain CSS, TikTok-style top/bottom `linear-gradient` scrims.
- **Done when:** `npm run build` exits 0; `grep -c 'playsInline' web/src/components/stage.tsx` ≥ 2 and `grep muted` matches both videos (WEB-02); `grep '#t=0.001' web/src/components/stage.tsx` matches (WEB-03); `grep 'started_at_ms' web/src/components/stage.tsx` matches the seek math (WEB-05); `grep -i 'shimmer\|hold' web/src/components/stage.tsx web/src/styles.css` matches (D-07).
- **Covers:** D-07 (client half), RESEARCH autoplay/preload pitfalls, GOAL "video plays"

### III. Instagram-poll vote overlay + countdown + HUD

- **Files:** `web/src/components/vote-overlay.tsx`, `web/src/components/hud.tsx`, `web/src/styles.css` (overlay/HUD sections)
- **Read first:** `web/src/lib/useEpisode.ts` (`vote`, `castVote`, `viewers`, `skewMs`), `tmp/interdimensional-game/components/hud.tsx` (rAF countdown + width-% bar — imitate), RESEARCH.md patterns note "frosted glass is net-new CSS"
- **Action:** Instagram-story poll card centered in the lower third: frosted glass (`backdrop-filter: blur(14px)` + translucent background + fallback solid rgba for non-supporting browsers), the vote `question` on top, one row per option. Before voting: tappable pills calling `castVote(idx)`. After `your_vote != null` or `locked`: rows become percentage bars — width = `tallies[i] / max(1, sum(tallies)) * 100`%, `transition: width 300ms ease`, percentage label, checkmark on the caller's pick, winner highlighted when `locked` with `winner_idx`. Countdown per WEB-04: rAF loop computing `remaining = vote.deadline_ms - (Date.now() + skewMs)`, rendered as seconds + a shrinking track bar, urgency style under 3s; unmount on `vote_closed` (`vote === null`). HUD: top-left LIVE badge, top-right viewer count from `viewers`. Overlay renders only when `vote != null`; stale `vote_update` after close must not resurrect it (the store already null-guards — don't duplicate state).
- **Done when:** `npm run build` and `npm run typecheck` exit 0; `grep 'backdrop-filter' web/src/styles.css` matches; `grep 'transition' web/src/styles.css` shows the width transition; `grep 'skewMs' web/src/components/vote-overlay.tsx` matches the deadline math (WEB-04).
- **Covers:** RESEARCH poll-bar/countdown patterns, GOAL "audience votes" (client)

## Nyquist criteria for this plan

- [ ] `npm run build` exits 0 with SPA mode + phoenix 1.8.13 pinned (WEB-01)
- [ ] Both players muted + playsInline behind a tap gate (WEB-02)
- [ ] Standby warms with `#t=0.001` + muted play/pause (WEB-03)
- [ ] Poll bars animate width; countdown uses `deadline_ms + skewMs` (WEB-04)
- [ ] Mount-time seek derives from `started_at_ms` across 10s segments (WEB-05)

## Risks accepted in this plan

- No web test runner exists; predicates verify via build/typecheck + source inspection. Runtime behavior against a live server is exercised in wave IV (Plan VII smoke) and by the sprint verifier.
- `backdrop-filter` performance on low-end mobile over video is unmeasured (LOW-confidence research note); solid-color fallback ships alongside.
- Real-device iOS verification is out of reach for the executor; the `#t=0.001` + warm-play mitigation follows multiple agreeing sources.
- Comments/share/next-episode-countdown chrome from PLOT.md §2 is deferred scope, not built.

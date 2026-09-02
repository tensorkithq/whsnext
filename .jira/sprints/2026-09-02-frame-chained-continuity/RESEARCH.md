# Research: 2026-09-02-frame-chained-continuity

**Date**: 2026-09-02
**Domain**: backend/realtime (Elixir) — surgical change on a verified-working loop
**Confidence**: HIGH
**Valid until**: 2026-10-02 — in-repo facts plus two fetched fal pages; only the audio-overhang sample size is thin

## Summary

Small sprint, three items, all fully mapped. (1) Frame chaining: `state.last_frame_url` has exactly two touchpoints — `nil` at init and the ctx read — and the pipeline deliberately skips extracting the final segment's frame (`pipeline.ex:127`). The natural hook is `run_segments/5`, shared by cycle and opening, with notify-before-extract already in place so the ~3s cost sits after segment delivery. With spike-measured timings the frame lands 3–6s before lock. (2) Winner reveal: replace the immediate `vote_closed` at `episode_server.ex:204` with a scheduled `{:timeline, :vote_close}` guarded on `%{vote: %{locked: true}}` — the guard alone kills the revote race, since a reopened vote is `locked: false`. Below-quorum close stays immediate (nothing to reveal; its synchronous cleanup conflicts with delay). (3) EP-08: supersede in this sprint's `features/`, don't rewrite the closed sprint's file.

The one genuine design point — what happens when the frame message straddles the beat bump at lock — resolves to **latest-wins storage via a dedicated `handle_info` head exempt from the beat guard** (patterns Q1, option b): tagging with beat+1 inverts the race (drops the on-time case), and server-side extraction at `:scene_boundary` is structurally too late (ctx is built at the +20s lock, boundary fires at +30s). The reference impl backs latest-wins (`engine.ts:97,250` stores lastFrame under a run token while verdicts stay beat-guarded). Two companion rules: refresh `pending_cycle`'s snapshot at dispatch (it captures ctx at lock — a frame arriving during a hold would otherwise be lost), and a failed trailing extraction must be non-fatal (reference: "the previous frame is still the ground truth") rather than flowing through `{:error, :frame, ...}` into a hold.

**Primary recommendation:** land frame chaining as (extract-after-final-segment in `run_segments` + latest-wins `{:last_frame, url}` head + ctx refresh at dispatch + non-fatal trailing extraction with `-sseof -1` retry for audio overhang), the reveal as (`reveal_ms` timing + scheduled `:vote_close` with locked-guard), and EP-08 as a superseding scenario in this sprint's feature file.

## Codebase

Full detail in `research-codebase.md`. Headlines (all path:line-cited there):

- **Gap:** `episode_server.ex:69` (init nil), `:418` (ctx read) are the only `last_frame_url` touchpoints; `pipeline.ex:127` (`next_frame(2, _url) → {:ok, nil}`) is the deliberate skip. Bridge→scene chaining already works (`pipeline.ex:47-48`).
- **Hook:** `run_segments/5` (`pipeline.ex:102-115`) has `dest`, `beat`, and segment url in scope; shared by `run_cycle` and `run_opening`; notify precedes extraction.
- **Timing:** lock at +20s; segment 2 lands ~+11–14s; extraction ~+14–17s (spike: i2v 4,940ms, last_frame 2,946ms) → 3–6s margin. A retry-delayed segment blows past lock; dropping/last-wins is acceptable either way (next cycle already dispatched with what it had).
- **Free bonus:** below-quorum locks don't bump the beat (`:174-179`) — frames survive revote rounds untouched.
- **Reveal:** `vote_locked`/`vote_closed` consecutive at `:203-204`; `schedule/2` + injectable `timings` (`:26-32,50,445`) is the mechanism; `:vote_close` is a free event name. Client needs no change: winner styling renders on `locked` (`vote-overlay.tsx:47,73`), the lag gate force-shows locked votes (`:17`), store nulls on `vote_closed` (`useEpisode.ts:52-66`).
- **Test blast radius:** exactly one break — `episode_server_test.exs:61` asserts `vote_closed` within 100ms of lock. Below-quorum closes (`:105,122,146`) unaffected; channel/integration tests never assert `vote_closed`; pipeline tests count i2v calls, not extractions. PipelineStub unchanged; FalMock `upload` already yields unique frame URLs and `fail_once(:upload)` exercises extraction failure.
- Optional (recovery/debug only): persist the frame URL in scene-beat `meta` — `store.ex:23-30` replaces meta wholesale, `schemas/beat.ex:19-21` casts it.

## Patterns & conventions

Full detail in `research-patterns.md`:

- **To imitate:** dedicated `handle_info` head before the beat-guard pair (`episode_server.ex:118-122`) storing latest-wins — mirrors the reference's run-token lastFrame vs beat-guarded verdicts split. Guarded-head + fall-through for `:vote_close` matching `%{vote: %{locked: true}}` (house precedents `:170/:182`, `:184/:193`). `reveal_ms` in the timings map per the test-injectable philosophy. Non-fatal trailing extraction (reference `engine.ts:283-288`).
- **To not imitate:** in-place rewrite of the closed sprint's feature file — it would attribute post-sprint behavior to `@plan:IV` and desynchronize the frozen 33/33 claim map. Supersede here with a fresh `@req` scenario + one comment above the old EP-08.
- **Keep `-sseof -0.25`** (byte-identical to reference recipe, spike-proven); add the overhang retry below.

## Common Pitfalls

### Audio outlasts video on real H3 Max clips (external, empirically verified)
- **What goes wrong:** `-sseof` measures from container duration; the AAC track can outlast the video stream, and an overhang >~0.2s seeks past the last video frame → ffmpeg exits non-zero ("Nothing was written into output file").
- **Evidence:** real spike clip overhang 0.06s (worked, frame at pts 9.917/10.083, byte-identical to spike's upload); synthetic 1s overhang failed at `-1`, recovered at `-1.05`.
- **How to avoid:** retry once with `-sseof -1` on non-zero exit (still inside the user's "last second" intent).
- **Warning signs:** `{:error, {:ffmpeg, _}}` from `Whn.Frames.last_frame/1` on clips that play fine.

### Frame message straddles the beat bump
- **What goes wrong:** beat increments at lock (`episode_server.ex:210`); a beat-guarded `{:last_frame, _}` sent late gets dropped, tagged-ahead gets dropped early.
- **How to avoid:** latest-wins exempt head (recommendation above); optional monotonic send-tag check if overwrite-by-older ever matters (planner call).

### `pending_cycle` snapshots stale ctx
- **What goes wrong:** the zero-viewer hold path captures ctx at lock (`episode_server.ex:221`); a frame arriving during the hold is silently unused.
- **How to avoid:** rebuild or patch `last_frame_url` into the ctx at dispatch time in the `:presence_check` hold branch.

### Delayed close vs revote
- **What goes wrong:** a scheduled `:vote_close` from a canonized lock could close a vote the below-quorum path already reopened.
- **How to avoid:** the `%{vote: %{locked: true}}` guard — reopened votes are `locked: false`; below-quorum close stays immediate and synchronous.

### Trailing extraction failure flips the episode to hold
- **What goes wrong:** routing the scene-end extraction failure through `{:pipeline, beat, {:error, :frame, _}}` (`pipeline.ex:134-138` → `episode_server.ex:265-268`) would hold a perfectly playable episode.
- **How to avoid:** trailing extraction is best-effort — log, skip the message, next bridge falls back to t2v exactly as today.

## Risks & unknowns

- **Audio-overhang size** sampled on one real clip (0.06s) — the `-1` retry gives ~0.96s headroom; accept and observe.
- **fal storage retention** has no documented number; empirically ≥2 days with `max-age=5184000, immutable` — 60s need is trivially safe (external, live-checked).
- **`end_image_url` on H3 Max i2v exists** (fetched) — recorded for a future "bridge ends on the next scene's opening frame" upgrade; out of scope now.
- **Reveal duration** — exact `reveal_ms` value (brief suggests ~2.5s) is product feel; planner picks, timings-injectable either way.

## Open questions for planner

- `reveal_ms` default (2_500 suggested).
- Monotonic beat check on the latest-wins frame head: worth it, or accept rare older-frame overwrite.
- `@req` id scheme for this sprint's feature file (fresh FC-xx series vs continuing EP-xx).
- Whether to persist the scene-end frame URL into beat `meta` (debug/recovery value vs an extra write).
- Client-side: anything needed during the 2.5s reveal window (research says no — confirm as a plan Done-when via existing build/grep gates).

## Sources

### Primary (HIGH confidence)
- Per-focus files with path:line cites throughout: `research-codebase.md` (episode_server.ex, pipeline.ex, tests, stubs, prior sprint CONTEXT/VERIFICATION), `research-patterns.md` (house idioms + reference impl engine.ts/frames.ts precedents), `research-external.md` (fetched: h3-max i2v /api page incl. `end_image_url`; ffmpeg docs + live extraction runs on the real spike clip with ffmpeg 9.0.1; live fal.media retention check; ffmpeg-api/extract-frame /api page — `frame_type` defaults to `"first"`, fallback must pass `"last"` explicitly).

### Secondary (MEDIUM confidence)
- Audio-overhang generality across H3 Max outputs (one real sample + synthetic reproductions).

### Tertiary (LOW confidence)
- None.

## Metadata

**Research scope:** codebase, patterns, external. Omitted sections: Architectural Responsibility Map (single-tier — all changes in the Phoenix server except one feature-file scenario), Standard Stack (no new deps), Don't Hand-Roll (no build-vs-buy surface), SOTA Updates (none relevant).

**Confidence breakdown:** codebase HIGH (read + line-cited); patterns HIGH (house precedents + vendored reference); external HIGH (fetched + empirical), except overhang generality MEDIUM.

**Valid-until reasoning:** 2026-10-02 — in-repo facts are stable on the branch; fal schema re-verify only if the endpoint versions.

---

*Sprint: 2026-09-02-frame-chained-continuity*
*Research completed: 2026-09-02*
*Next step: `/jira:plan`*

# Brief: 2026-09-02-frame-chained-continuity

**Created:** 2026-09-02
**Source:** user-prompt
**Issue:** none

## Statement

Frame-chained continuity for the live episode loop. User-confirmed direction (2026-09-02), in their words: "At the end of the last frame, you take a snapshot of that frame, the last second in that frame, and then use that as the basis for the next one. … you take the last thing to create the bridge, which is the connection to the voted option. When we have the votes, the last frame of the bridge is then sent as the starting frame shots of the prompt for the selected option."

Concretely, three items:

1. **Scene-end frame chaining.** At the end of each scene's final segment, snapshot its last frame and carry it into the next cycle: the bridge is generated i2v FROM that scene-end frame (the visual connection to the voted option); the bridge's last frame then seeds the winning option's next scene. Preserve the generation-buffer overlap: bridge generates during remaining scene playback; next scene's first segment during bridge playback. Today `Whn.EpisodeServer` never writes `state.last_frame_url` after init and `Whn.Pipeline` never extracts the FINAL segment's frame, so production bridges fall back to t2v — the bridge→scene half of the chain exists and is tested but is unreachable (verifier finding #1, sprint 2026-08-31-live-episode-mvp).
2. **Winner reveal.** The server broadcasts `vote_closed` immediately after `vote_locked`, so the client tears the poll down before the winner highlight renders. Delay `vote_closed` ~2.5s after lock so the audience sees what won.
3. **Hygiene.** `features/episode-core.feature` EP-08 predicate is stale after the post-sprint quorum-guard change (`min_voters` ≥2 supersedes zero-presence hold at lock).

## Constraints

- The pinned pipeline message contract (previous sprint's CONTEXT.md) gains at most one message (shape like `{:pipeline, beat, {:last_frame, url}}`); everything else conforms to the existing pinned interfaces.
- `Whn.Frames.last_frame/1` exists and costs ~3s per call (spike-measured) — the scene-end extraction must sit off the critical path (after the final segment is delivered, well before the next lock).
- Frozen wire protocol (`web/src/lib/types.ts` / `useEpisode.ts`) unchanged — the winner-reveal delay is server-side timing only; the client already renders the locked state when given time.
- Post-sprint changes already on the branch and must stay intact: quorum guard (`min_voters`, default 2), English-only prompts, client playhead vote gating.
- Tests hermetic (FalMock / PipelineStub / Req.Test); no live fal or Celeris spend.

## Out of scope

- Speculative branch generation, prod hardening (releases, check_origin), episode duration caps, comments/share features.
- Reworking the vote flow beyond the reveal delay.
- Backend-restart recovery.

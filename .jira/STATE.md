---
project: whn
created: 2026-08-31
last_activity: 2026-09-02
active_sprint: 2026-09-02-escalation-engine-pot-grows
---

# State

Project-wide state for the `jira` workflow. The orchestrator commands keep this current.

## Sprints

<!-- One row per sprint. Most recent first. -->

| Slug | Status | Goal | Outcome |
|------|--------|------|---------|
| 2026-09-02-escalation-engine-pot-grows | planned | Server-owned absurdity ladder: `absurdity_level` +1 per canonized vote lock, L0–L5 fragments into script + video prompts, votes pick escalation form ([#8](https://github.com/tensorkithq/whn/issues/8)) | — |
| 2026-09-02-frame-chained-continuity | done | Scene-end frame seeds the bridge, bridge-end seeds the next scene; winner reveal delay; EP-08 hygiene | PASS (11/11 outcomes, 9/9 predicates, 49 tests) — rides [PR #6](https://github.com/tensorkithq/whn/pull/6) |
| 2026-08-31-live-episode-mvp | done | One live episode: video → 10s vote → winner-only generated continuation, TikTok-style mobile client | PASS (8/8 outcomes, 33/33 predicates, 37 tests) — [PR #6](https://github.com/tensorkithq/whn/pull/6) |

Status legend: `researching`, `planned`, `executing`, `verifying`, `done`, `blocked`, `abandoned`.

## Decisions log

<!-- Cross-sprint decisions worth remembering. Each as one bullet with the date and the sprint where it was made. -->

2026-08-31, sprint 2026-08-31-live-episode-mvp (full text in its CONTEXT.md):

- D-01 votes: one per anon_id per decision, immutable; dup replies ok with original pick; unique index backstop
- D-02 tie-break: lowest option index among tied leaders
- D-03 vote_update: immediate per-vote broadcast, no batching
- D-04 topic: client `episode:live` → `Whn.Episodes.current/0`
- D-05 Celeris (revised 2026-08-31): real Celeris API — OpenAI-compatible chat completions, `celeris-1`, Bearer CELERIS_KEY from .env; text-only, fal vision route demoted to fallback
- D-06 frames: local ffmpeg (`-sseof -0.25`) + FalEx.Storage.upload; hosted extract-frame documented only
- D-07 hold: first-class phase; freeze last frame + shimmer
- D-08 web phoenix npm → 1.8.13
- D-09 ports: Postgres 57432 in dev+test Repo config; HTTP 57400 in dev.exs + runtime.exs default + flake PORT export
- D-10 web/: fresh TanStack Start scaffold, SPA mode; src/lib drafts + proxy + meta ported verbatim
- D-11 fal client: fal_ex ~> 0.1.0 behind `Whn.Fal` behaviour; req for downloads
- D-12 cost guard: no generation cycle at zero presence
- D-13 seed: Lagos Wahala "Salary Just Entered"
- D-14 timing: 3×10s segments; vote +10s, lock +20s; timings test-injectable, transitions via send_after self-messages
- D-15 failures: one retry per fal stage (same seed); Celeris retry once then canned fallback; votes never reopen
- D-16 secrets: FAL_KEY in gitignored .env, flake shellHook sources it; .env.example committed

2026-09-02, sprint 2026-09-02-frame-chained-continuity (full text in its CONTEXT.md):

- Frame chaining: pipeline extracts the FINAL segment's frame (best-effort, -sseof -1 overhang retry) and emits one new pinned message {:last_frame, url}; server stores it latest-wins via a beat-guard-exempt head; ctx refreshed at pending_cycle dispatch; trailing extraction failure never holds the episode (t2v fallback as before)
- Winner reveal: vote_closed scheduled reveal_ms (2_500 default, timings-injectable) after vote_locked, guarded on locked: true; below-quorum close stays immediate
- EP-08 superseded by REV-03 in this sprint's features/ (comment-only annotation on the old scenario; tags/text untouched)
- Deferred: end_image_url keyframe bridges, monotonic frame check, beat-meta frame persistence

2026-09-02, sprint 2026-09-02-escalation-engine-pot-grows (full text in its CONTEXT.md):

- D-01 base branch: sprint branch `jira/2026-09-02-escalation-engine-pot-grows` off gen/speakless (sectioned prompt format lives only there); PR targets main carrying cb99238
- D-02 level: `absurdity_level` server-owned in EpisodeServer, +1 beside the beat bump in `lock_and_start_cycle/2` only; NEVER mirrored into story_state (updates-win merge is model-clobber-able)
- D-03 ctx contract amendment: ctx gains required key `absurdity_level` (strict access, crash if missing); all prior frame-chained shapes unchanged
- D-04 ladder: 6-element `@ladder` in `Whn.Prompts` behind `escalation_fragment(level)` clamping at `min(level, 5)`; premise-neutral defaults, attrs override deferred to #11
- D-05 injection: labeled single-line appends — `ESCALATION (Ln):` in the user prompt, mechanical `\nEscalation: fragment` via `finalize/2` on bridge + scene (post-squeeze, pre-Style; fallback rides free), opening flux still carries L0
- D-06 options: escalation-form via system-prompt rules (three forms of the same beat, never whether); mechanical floor stays schema-3 + clamp + dedup
- D-07 fallback choices stay generic — recorded degradation
- D-08 dedup: `Enum.uniq` + backfill excluding kept strings in `choices/1`
- D-09 raw counter unbounded; only fragment lookup clamps to L5 (lock 6 per #9's arithmetic renders the L5 fragment)
- D-10 persistence: none, in-memory like beat (third sprint reconfirming)

## Blockers

<!-- Active blockers across all sprints. Resolved blockers move to the Decisions log. -->

None active. The two PR #6 follow-ups (frame chaining production-dead; winner reveal unreachable) were resolved by sprint 2026-09-02-frame-chained-continuity. Remaining accepted risk: the frame chain is mock-verified; live-fal visual continuity awaits a production smoke.

## Notes

<!-- Free-form workflow notes, accumulated lessons, links to recurring patterns. -->

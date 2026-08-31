---
project: whn
created: 2026-08-31
last_activity: 2026-08-31
active_sprint: 2026-08-31-live-episode-mvp
---

# State

Project-wide state for the `jira` workflow. The orchestrator commands keep this current.

## Sprints

<!-- One row per sprint. Most recent first. -->

| Slug | Status | Goal | Outcome |
|------|--------|------|---------|
| 2026-08-31-live-episode-mvp | planned | One live episode: video → 10s vote → winner-only generated continuation, TikTok-style mobile client | — |

Status legend: `researching`, `planned`, `executing`, `verifying`, `done`, `blocked`, `abandoned`.

## Decisions log

<!-- Cross-sprint decisions worth remembering. Each as one bullet with the date and the sprint where it was made. -->

2026-08-31, sprint 2026-08-31-live-episode-mvp (full text in its CONTEXT.md):

- D-01 votes: one per anon_id per decision, immutable; dup replies ok with original pick; unique index backstop
- D-02 tie-break: lowest option index among tied leaders
- D-03 vote_update: immediate per-vote broadcast, no batching
- D-04 topic: client `episode:live` → `Whn.Episodes.current/0`
- D-05 Celeris: fal `openrouter/router/vision`, `google/gemini-2.5-flash-lite`, latest frame always attached
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

## Blockers

<!-- Active blockers across all sprints. Resolved blockers move to the Decisions log. -->

## Notes

<!-- Free-form workflow notes, accumulated lessons, links to recurring patterns. -->

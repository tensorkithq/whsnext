# Issues — 2026-08-31-live-episode-mvp

Five track issues cut from the 7 wave-plans (user chose the 5-track merge: plans III+VI fold into the pipeline issue; plan VII folds into episode core, with its Store helper in persistence).

| # | Issue | Title | Type | Plans | Status |
|---|---|---|---|---|---|
| 1 | [#1](https://github.com/tensorkithq/whn/issues/1) | DevX: pin Phoenix 57400 + Postgres 57432, .env FAL_KEY wiring, run docs | AFK | I | open |
| 2 | [#2](https://github.com/tensorkithq/whn/issues/2) | Web: TanStack Start SPA — vertical dual-player stage, Instagram-poll vote overlay, server-synced 10s countdown | AFK | II | open |
| 3 | [#3](https://github.com/tensorkithq/whn/issues/3) | Persistence: episodes/beats/decisions/votes tables + Store context with one-vote-per-viewer backstop | AFK | V (+VII Store helper) | open |
| 4 | [#4](https://github.com/tensorkithq/whn/issues/4) | Episode core: EpisodeServer state machine + episode:live channel + presence + voting, wired to store/pipeline, seeded with Lagos Wahala | AFK | IV + VII | open |
| 5 | [#5](https://github.com/tensorkithq/whn/issues/5) | Generation pipeline: fal client wrapper + last-frame extraction + timed latency spike + Celeris script engine + winner-only cycle | AFK | III + VI | open |

## Dependency chain

```
#1 ──┬── #3 (persistence)
     ├── #4 (episode core: state machine/channel half)
     ├── #5 (pipeline: foundation half; cycle half also needs #4's supervision skeleton)
     └── (#2 web has no blockers)
#3 + #5 ──→ #4 (wiring + e2e half)
```

Execution still runs wave-by-wave from the 7 plans (`/jira:execute`); these issues are the track-level tracking surface.

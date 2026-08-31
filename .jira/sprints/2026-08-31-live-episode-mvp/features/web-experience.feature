@sprint:2026-08-31-live-episode-mvp
Feature: TikTok-style vertical stage with Instagram-poll voting

  @req:WEB-01 @plan:II @wave:1
  Scenario: web/ is a TanStack Start SPA that builds
    Given the re-bootstrapped web/ workspace
    When npm run build runs
    Then it exits 0, the vite config enables tanstackStart SPA mode, and package.json pins phoenix 1.8.13

  @req:WEB-02 @plan:II @wave:1
  Scenario: Mobile playback survives autoplay policy
    Given the stage component source
    When it is inspected for playback attributes
    Then both video elements carry muted and playsInline and playback starts behind a tap-to-start gate

  @req:WEB-03 @plan:II @wave:1
  Scenario: Standby player warms the next clip
    Given the dual-player stage
    When a preload broadcast delivers URLs
    Then the standby video receives the URL with a #t=0.001 fragment and a muted play-then-pause warm

  @req:WEB-04 @plan:II @wave:1
  Scenario: Instagram-style poll renders live percentages and a synced countdown
    Given an open vote in the episode store
    When the vote overlay renders
    Then options render as width-percentage bars with a CSS width transition, the caller's pick is marked, and the countdown derives from deadline_ms plus skewMs

  @req:WEB-05 @plan:II @wave:1
  Scenario: Late joiner seeks to the server clock
    Given a playback whose started_at_ms is in the past
    When the stage mounts
    Then the active player selects the segment and offset from (server now minus started_at_ms) across 10s segments

@sprint:2026-08-31-live-episode-mvp
Feature: fal reachable from Elixir with measured latency

  @req:FAL-01 @plan:III @wave:2
  Scenario: One wrapper isolates fal_ex
    Given server/lib/whn/fal.ex
    When mix compile --warnings-as-errors runs
    Then it exits 0 and Whn.Fal exposes t2v/2, i2v/3, flux/2, vision/2, and upload/1 dispatching to a configurable impl

  @req:FAL-02 @plan:III @wave:2
  Scenario: Last frame extracted locally
    Given a locally generated mp4 fixture
    When Whn.Frames.last_frame/1 runs with upload stubbed
    Then a jpg is produced via ffmpeg -sseof -0.25 and the test exits 0

  @req:FAL-03 @plan:III @wave:2
  Scenario: Generation latency measured, not assumed
    Given FAL_KEY in the environment
    When mix run scripts/fal_spike.exs completes
    Then .jira/sprints/2026-08-31-live-episode-mvp/fal-spike.log records wall-clock ms for flux 720x1280, i2v 10s 480P from a hosted frame URL, t2v 10s 9:16, a last-frame round-trip, and a vision call with an image attached

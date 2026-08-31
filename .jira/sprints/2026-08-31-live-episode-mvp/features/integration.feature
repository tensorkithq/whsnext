@sprint:2026-08-31-live-episode-mvp
Feature: The loop closes end to end

  @req:E2E-01 @plan:VII @wave:4
  Scenario: The seed episode boots
    Given migrated tables and the Lagos Wahala seed content
    When Whn.Episodes.start!/1 runs with a stub pipeline
    Then an episodes row exists for "Salary Just Entered" and a Registry-registered EpisodeServer broadcasts phase

  @req:E2E-02 @plan:VII @wave:4
  Scenario: A full cycle persists its truth
    Given a booted episode with stubbed fal and a sandboxed database
    When a driven cycle runs vote open, votes, lock, and pipeline stage messages
    Then decisions, votes, and beats rows exist with the locked winner and segment URLs

  @req:E2E-03 @plan:VII @wave:4
  Scenario: The merged tree is clean
    Given all waves merged
    When mix precommit runs in server/ and npm run build runs in web/
    Then both exit 0

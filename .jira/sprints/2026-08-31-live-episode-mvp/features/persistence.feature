@sprint:2026-08-31-live-episode-mvp
Feature: Episode truth survives in Postgres

  @req:DB-01 @plan:V @wave:2
  Scenario: Schema migrates
    Given the flake Postgres on 57432
    When mix ecto.migrate runs
    Then it exits 0 and the episodes, beats, decisions, and votes tables exist

  @req:DB-02 @plan:V @wave:2
  Scenario: Duplicate votes cannot persist
    Given a stored decision
    When Whn.Store.record_vote/3 runs twice with the same decision_id and anon_id
    Then exactly one votes row exists for the pair

  @req:DB-03 @plan:V @wave:2
  Scenario: A beat round-trips
    Given a created episode
    When a beat with segment URLs, a decision with a winner, and a story-state update are stored
    Then they read back with matching fields

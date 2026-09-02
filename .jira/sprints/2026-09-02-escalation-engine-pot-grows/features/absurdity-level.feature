@sprint:2026-09-02-escalation-engine-pot-grows
Feature: The server owns the absurdity level and bumps it once per canonized lock

  @req:EL-01 @plan:I @wave:1
  Scenario: A canonized vote lock bumps the level by exactly one
    Given an episode server at absurdity_level 0 with an open vote at quorum
    When the vote locks and canonizes a winner
    Then the dispatched start_cycle ctx carries absurdity_level 1 and state.absurdity_level is 1

  @req:EL-02 @plan:I @wave:1
  Scenario: Below-quorum closes and revotes never bump the level
    Given an episode server whose open vote is below quorum at lock time
    When the poll closes without a winner, revotes, and later locks with quorum
    Then absurdity_level stays 0 through the close and revote, and the eventual start_cycle ctx carries 1, not 2

  @req:EL-03 @plan:I @wave:1
  Scenario: The script engine cannot clobber the level
    Given a celeris result whose story_state_updates contain an "absurdity_level" key
    When the server merges the updates and the next quorum vote locks
    Then the dispatched ctx carries the server-owned level, unaffected by the model's value

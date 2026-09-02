@sprint:2026-09-02-frame-chained-continuity
Feature: The audience sees what won before the poll tears down

  @req:REV-01 @plan:I @wave:1
  Scenario: vote_closed waits for the reveal window
    Given a vote locked with quorum
    When vote_locked broadcasts
    Then vote_closed is not broadcast in the same handler and broadcasts only when the scheduled :vote_close timeline event fires with the vote still locked

  @req:REV-02 @plan:I @wave:1
  Scenario: A stale vote_close falls through
    Given a vote that is no longer locked (already closed, or reopened for the next beat)
    When a :vote_close timeline event fires
    Then no vote_closed is broadcast and an open poll is untouched

  # Supersedes @req:EP-08 of 2026-08-31-live-episode-mvp: the quorum guard
  # (min_voters, commit ba56bb2) replaced the zero-presence hold at lock.
  @req:REV-03 @plan:I @wave:1
  Scenario: Below quorum the poll closes immediately without a winner
    Given fewer than min_voters distinct voters when the lock fires
    When the vote_lock timeline event is delivered
    Then vote_closed broadcasts immediately with no vote_locked and no reveal scheduling, the same options re-offer via revote, and no generation starts

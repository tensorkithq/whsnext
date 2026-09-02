@sprint:2026-08-31-live-episode-mvp
Feature: Server-authoritative live episode with synchronized voting

  @req:EP-01 @plan:IV @wave:2
  Scenario: Join replies with full sync
    Given a running EpisodeServer and a channel client carrying an anon_id
    When the client joins "episode:live"
    Then the ok reply contains phase, episode, now_ms, playback, and vote

  @req:EP-02 @plan:IV @wave:2
  Scenario: Presence counts viewers
    Given a joined channel client
    When after_join tracking completes
    Then a presence_state push lists the client keyed by anon_id

  @req:EP-03 @plan:IV @wave:2
  Scenario: One immutable vote per anon identity
    Given an open vote
    When one anon_id pushes "vote" twice with different option_idx values
    Then both replies return tallies and your_vote and the second push changes neither

  @req:EP-04 @plan:IV @wave:2
  Scenario: Votes after lock are rejected
    Given a locked vote
    When a client pushes "vote"
    Then the reply is an error with reason "locked"

  @req:EP-05 @plan:IV @wave:2
  Scenario: Timeline opens, locks, and tie-breaks deterministically
    Given a scene started with test-driven timeline messages
    When the vote-open message then the lock message are delivered
    Then vote_open broadcasts with a deadline_ms 10s out and lock picks the max tally with lowest index winning ties

  @req:EP-06 @plan:IV @wave:2
  Scenario: Hold is a state, not an error
    Given a scene whose final segment ends with no next playback ready
    When the scene-boundary message fires
    Then phase "hold" is broadcast and a later segment_ready message resumes live playback

  @req:EP-07 @plan:IV @wave:2
  Scenario: Server owns every clock
    Given broadcasts from a driven cycle
    When vote_open and playback payloads are inspected
    Then deadline_ms and started_at_ms are absolute server epoch milliseconds

  # Superseded 2026-09-02 by @req:REV-03 (2026-09-02-frame-chained-continuity): the quorum guard (min_voters, commit ba56bb2) replaced the zero-presence hold at lock. Preserved verbatim for this sprint's claim map.
  @req:EP-08 @plan:IV @wave:2
  Scenario: Zero viewers stop the spend
    Given an episode booted with no presence entries
    When the opening or a generation cycle would start
    Then the pipeline impl is not invoked and the episode holds

  @req:EP-09 @plan:IV @wave:2
  Scenario: Viewers present trigger the opening
    Given a freshly booted episode with at least one presence entry
    When the opening trigger fires
    Then pipeline_impl().start_opening/2 is invoked with winning_choice and last_frame_url nil

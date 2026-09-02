@sprint:2026-09-02-frame-chained-continuity
Feature: Scene-end frames chain each cycle into the next

  @req:FC-01 @plan:II @wave:2
  Scenario: The pipeline emits the scene-end frame after the final segment
    Given a generation cycle running against the mocked fal client
    When the third segment has been delivered
    Then a {:pipeline, beat, {:last_frame, url}} message arrives after {:segment_ready, 2, _} and no error is reported

  @req:FC-02 @plan:I @wave:1
  Scenario: The stored frame seeds the next cycle's bridge
    Given an episode server that received {:last_frame, url} for the current scene
    When a quorum vote lock dispatches the next cycle
    Then the start_cycle ctx carries last_frame_url equal to that url

  @req:FC-03 @plan:I @wave:1
  Scenario: Frame intake is exempt from the stale-beat guard
    Given an episode server whose current beat differs from the message's beat tag
    When a {:last_frame, url} message arrives
    Then state.last_frame_url is updated to that url (latest write wins)

  @req:FC-04 @plan:II @wave:2
  Scenario: A failed trailing extraction never degrades the episode
    Given the fal upload armed to fail on the trailing extraction's call
    When the cycle's final segment completes
    Then all three segment_ready messages were delivered, no {:error, :frame, _} is reported, and no {:last_frame, _} is emitted

  @req:FC-05 @plan:I @wave:1
  Scenario: A frame arriving during a hold seeds the deferred cycle
    Given a quorum lock that parked its cycle because zero viewers were present
    When {:last_frame, url} arrives during the hold and presence returns
    Then the dispatched start_cycle ctx carries last_frame_url equal to that url

  @req:FC-06 @plan:II @wave:2
  Scenario: Audio overhang does not break last-frame extraction
    Given a clip whose audio track outlasts its video by about half a second
    When Whn.Frames.last_frame runs on it
    Then it returns {:ok, url} by retrying the extraction with -sseof -1

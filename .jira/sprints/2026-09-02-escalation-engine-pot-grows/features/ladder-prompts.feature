@sprint:2026-09-02-escalation-engine-pot-grows
Feature: Ladder fragments reach every prompt surface and votes pick the escalation's form

  @req:EL-04 @plan:II @wave:2
  Scenario: The Celeris user prompt carries the level's ESCALATION line
    Given a pipeline ctx with absurdity_level 2
    When Prompts.user_prompt renders the ctx
    Then the prompt contains one line "ESCALATION (L2): " followed by the L2 ladder fragment

  @req:EL-05 @plan:II @wave:2
  Scenario: Finalize mechanically appends the fragment to both video prompts
    Given a valid Celeris reply, including one with a quoted dialogue line
    When Celeris.run finalizes it at absurdity_level 2
    Then both the bridge and next_scene video_prompts carry one "\nEscalation: " line with the L2 fragment, placed before the terminal Style suffix and intact after dialogue clamping

  @req:EL-06 @plan:II @wave:2
  Scenario: The canned fallback beat still carries the ladder fragment
    Given Celeris replies with garbage twice at absurdity_level 2
    When the run falls back to the canned beat
    Then both fallback video_prompts carry the "\nEscalation: " line with the L2 fragment

  @req:EL-07 @plan:II @wave:2
  Scenario: Levels above the ladder top clamp to L5
    Given an absurdity_level greater than 5
    When the fragment is looked up and the user prompt is rendered
    Then the L5 fragment is returned and the ESCALATION label reads "(L5)"

  @req:EL-08 @plan:II @wave:2
  Scenario: The system prompt makes options escalation-form and escalation server-owned
    Given the script-engine system prompt
    When its rules are inspected
    Then it states that the ESCALATION line is story truth the model must render and never decide, and that next_choices are three distinct forms of the same next beat, never whether the story escalates

  @req:EL-09 @plan:II @wave:2
  Scenario: Duplicate options are deduped and backfilled mechanically
    Given a Celeris reply whose next_choices contain duplicates
    When choices are clamped
    Then the result is exactly 3 distinct options, backfilled from the fallback choices without reintroducing a duplicate

  @req:EL-10 @plan:III @wave:3
  Scenario: Emitted video prompts carry the level's fragment at every ladder level
    Given a generation cycle against the mocked fal client at each absurdity_level 0 through 5
    When the cycle's bridge and segment prompts are captured
    Then every captured i2v prompt contains that level's ladder fragment

  @req:EL-11 @plan:III @wave:3
  Scenario: The opening still is the L0 anchor
    Given an opening run with a ctx at absurdity_level 0
    When the flux prompt is captured from the mocked fal client
    Then it contains "Escalation: " followed by the L0 ladder fragment

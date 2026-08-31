@sprint:2026-08-31-live-episode-mvp
Feature: Winner-only generation pipeline with a disciplined script engine

  @req:CEL-01 @plan:VI @wave:3
  Scenario: Celeris parses the README §5 contract
    Given a stubbed script-engine reply containing valid contract JSON
    When Whn.Celeris.run/1 executes
    Then it returns scene_summary, winning_choice, bridge, next_scene, next_choices, and story_state_updates

  @req:CEL-02 @plan:VI @wave:3
  Scenario: Malformed LLM output never stalls the episode
    Given a script-engine reply wrapped in markdown fences and a second reply of pure garbage
    When Whn.Celeris.run/1 executes against each
    Then the fenced reply parses via brace-slice extraction and the garbage reply yields the canned fallback without raising

  @req:CEL-03 @plan:VI @wave:3
  Scenario: Prompt discipline is baked in
    Given the Celeris system prompt and video-prompt builder
    When they are inspected
    Then final-frame hygiene and the wordless-sound clause are present and every video_prompt gains the vertical camera/style suffix

  @req:CEL-04 @plan:VI @wave:3
  Scenario: The pipeline reports stages as messages
    Given a mocked Whn.Fal impl
    When Whn.Pipeline.start_cycle/2 runs to completion
    Then the dest pid receives the celeris message, then bridge_ready, then segment_ready 0 through 2 in order

  @req:CEL-05 @plan:VI @wave:3
  Scenario: Generation params match the reference contract
    Given the mocked Whn.Fal call log after a full cycle and an opening
    When the calls are inspected
    Then i2v calls carry resolution "480P", duration 10, prompt_expansion_mode "disabled", and seed = episode seed + beat, and the opening flux call requests 720x1280

  @req:CEL-06 @plan:VI @wave:3
  Scenario: Failed generation retries once, idempotently
    Given a Whn.Fal impl that fails the first segment call then succeeds
    When the cycle runs
    Then the segment call is retried once with the same seed and no error message is sent

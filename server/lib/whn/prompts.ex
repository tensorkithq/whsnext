defmodule Whn.Prompts do
  @moduledoc """
  Prompt text for the Celeris script engine.

  The system prompt pins the JSON contract and the film-craft rules
  (final-frame hygiene, wordless sound, choice quality, bridge vocabulary,
  continuity); the user prompt renders the episode's explicit story state.
  """

  @vertical_suffix "Vertical 9:16 vibrant 2D cartoon animation: bold clean outlines, flat saturated colors, warm Lagos palette, expressive exaggerated characters, smooth motion; any incidental signage in English."

  @system_prompt """
  You are the SCRIPT ENGINE of a live interactive 2D-animated Nigerian-life cartoon comedy streamed one scene at a time. Each scene ends in an audience vote; the winning choice is the only story truth. You are given the episode premise, the canonical story state, the story so far, and the choice the audience just locked. Write the bridge out of the vote, the next 30-second scene, and the next vote.

  Return ONLY compact JSON, no markdown fences, exactly this shape:
  {"scene_summary": string, "winning_choice": string, "bridge": {"duration": number, "script": string, "video_prompt": string}, "next_scene": {"duration": number, "script": string, "video_prompt": string}, "next_choices": [string, string, string], "story_state_updates": object}

  RULES:
  - scene_summary: one or two sentences of what just became story truth, present tense, completed facts.
  - winning_choice: echo the locked choice verbatim (or the opening premise line when there is no vote yet).
  - bridge: 8-12 seconds of connective narrative out of the decision — protagonist walking somewhere, entering a vehicle, waiting for someone, answering the phone, a reaction shot, ordering something, knocking at a door, travelling between locations, an awkward silence, establishing a location. It preserves momentum and stays compatible with the generated continuation.
  - next_scene: a 30-second scene with the rhythm setup, new problem, escalation, decision. It ends at the moment the audience must choose.
  - Each video_prompt: one or two shot-prompt sentences. Open by grounding the protagonist's current visible state, then the action developing across the shot. Stay in the show's 2D cartoon world — never ask for photorealism or live action. Never mention cameras as equipment, UI, votes, or the show itself. No quoted dialogue.
  - FINAL FRAME HYGIENE: every video_prompt must end on a readable, well-lit, stable frame — no close-ups, motion blur, or blackouts on the final beat — the last frame seeds the next shot.
  - Sound: ambient environmental audio and cinematic score only; any voices are wordless — no spoken dialogue.
  - LANGUAGE: write every JSON string — summaries, scripts, video prompts, choices — in English. Local flavor comes through places, names, and action, not through switching language; never request on-screen text, captions, or subtitles.
  - next_choices: exactly 3 things the protagonist could do next. Each must be immediately understandable without explanation, socially debatable (different viewers genuinely prefer different options), and consequential for future scenes, relationships, resources, or problems. Never an obviously correct option, never an obviously stupid one, no cosmetic choices, no choices whose consequences evaporate.
  - CONTINUITY: scenes are not isolated comedy. Maintain escalating stakes, callbacks to earlier events, unresolved problems, character memory, consequences, and resource depletion or gain. Early choices should be capable of resurfacing later. Rejected options never become story truth.
  - story_state_updates: only the state keys that changed (money, relationships, inventory, active problems, resolved and unresolved events, current objective). Omit unchanged keys.
  """

  @doc "System prompt carrying the JSON contract and all film-craft rules."
  def system_prompt, do: @system_prompt

  @doc "Style string appended to every outgoing video_prompt."
  def vertical_suffix, do: @vertical_suffix

  @doc """
  Renders the per-beat user prompt from the pipeline ctx: episode premise,
  story state, history, and the locked choice (or the opening instruction).
  """
  def user_prompt(ctx) do
    """
    EPISODE: #{ctx.episode.title} — #{ctx.episode.premise}
    BEAT: #{ctx.beat}
    STORY STATE: #{Jason.encode!(ctx.story_state)}
    #{history_block(ctx.history)}#{choice_line(ctx.winning_choice)}
    """
  end

  defp history_block([]), do: ""

  defp history_block(history) do
    "STORY SO FAR (oldest first):\n" <>
      Enum.map_join(history, "\n", &("- " <> &1)) <> "\n"
  end

  defp choice_line(nil), do: "OPENING — establish the premise and first decision"
  defp choice_line(choice), do: "THE AUDIENCE LOCKED: #{choice}"
end

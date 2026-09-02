defmodule Whn.Prompts do
  @moduledoc """
  Prompt text for the Celeris script engine.

  The system prompt pins the JSON contract and the film-craft rules
  (final-frame hygiene, wordless sound, choice quality, bridge vocabulary,
  continuity); the user prompt renders the episode's explicit story state.
  """

  @vertical_suffix "Vertical 9:16 vibrant 2D cartoon animation: bold clean outlines, flat saturated colors, warm Lagos palette, expressive exaggerated characters, smooth motion; any incidental signage in English; any spoken words are clear English from a single on-screen speaker."

  @system_prompt """
  You are the SCRIPT ENGINE of a live interactive 2D-animated Nigerian-life cartoon comedy streamed one scene at a time. Each scene ends in an audience vote; the winning choice is the only story truth. You are given the episode premise, the canonical story state, the story so far, and the choice the audience just locked. Write the bridge out of the vote, the next 30-second scene, and the next vote.

  Return ONLY compact JSON, no markdown fences, exactly this shape:
  {"scene_summary": string, "winning_choice": string, "bridge": {"duration": number, "script": string, "video_prompt": string}, "next_scene": {"duration": number, "script": string, "video_prompt": string}, "next_choices": [string, string, string], "story_state_updates": object}

  RULES:
  - scene_summary: one or two sentences of what just became story truth, present tense, completed facts.
  - winning_choice: echo the locked choice verbatim (or the opening premise line when there is no vote yet).
  - bridge: 8-12 seconds of connective narrative out of the decision — protagonist walking somewhere, entering a vehicle, waiting for someone, answering the phone, a reaction shot, ordering something, knocking at a door, travelling between locations, an awkward silence, establishing a location. It preserves momentum and stays compatible with the generated continuation.
  - next_scene: a 30-second scene with the rhythm setup, new problem, escalation, decision. It ends at the moment the audience must choose.
  - Each video_prompt: one or two shot-prompt sentences. Open by grounding the protagonist's current visible state, then the action developing across the shot. Stay in the show's 2D cartoon world — never ask for photorealism or live action. Never mention cameras as equipment, UI, votes, or the show itself.
  - FINAL FRAME HYGIENE: every video_prompt must end on a readable, well-lit, stable frame — no close-ups, motion blur, or blackouts on the final beat — the last frame seeds the next shot.
  - Sound: ambient environmental audio and cinematic score, with expressive but wordless vocal reactions — laughs, gasps, exclamations, grunts — layered over them. DIALOGUE: scene clips only — at most ONE character speaks per scene clip, one short English line, at most 12 words (about five seconds of speech), written into the video_prompt as quoted dialogue, e.g. Tunde says: "Not today, sir, please." The line lands MID-SHOT: action establishes first, never speech in the opening seconds, and the line finishes before the final beat. Every other voice stays wordless-expressive; never two speakers in one clip; a clip with nothing worth saying carries reactions only. The bridge is ALWAYS dialogue-free — wordless reactions only.
  - LANGUAGE: write every JSON string — summaries, scripts, video prompts, choices — in English. Local flavor comes through places, names, and action, not through switching language; never request on-screen text, captions, or subtitles.
  - next_choices: exactly 3 things the protagonist could do next. Each must be immediately understandable without explanation, socially debatable (different viewers genuinely prefer different options), and consequential for future scenes, relationships, resources, or problems. Never an obviously correct option, never an obviously stupid one, no cosmetic choices, no choices whose consequences evaporate.
  - CONTINUITY: scenes are not isolated comedy. Maintain escalating stakes, callbacks to earlier events, unresolved problems, character memory, consequences, and resource depletion or gain. Early choices should be capable of resurfacing later. Rejected options never become story truth.
  - story_state_updates: only the state keys that changed (money, relationships, inventory, active problems, resolved and unresolved events, current objective). Omit unchanged keys.
  """

  @doc "System prompt carrying the JSON contract and all film-craft rules."
  def system_prompt, do: @system_prompt

  @doc "Style string appended to every outgoing video_prompt."
  def vertical_suffix, do: @vertical_suffix

  # ~5 seconds of speech. Enforced mechanically, not just requested:
  # the model's output is untrusted like every other field.
  @max_dialogue_words 12
  @quoted ~r/"[^"]+"/

  @doc """
  Keeps only the first quoted dialogue line, truncated to the word cap;
  any further quoted spans are removed. Used on scene video_prompts.
  """
  def clamp_dialogue(prompt) do
    case Regex.run(@quoted, prompt, return: :index) do
      nil ->
        prompt

      [{start, len}] ->
        head = binary_part(prompt, 0, start)
        quoted = binary_part(prompt, start, len)
        rest = binary_part(prompt, start + len, byte_size(prompt) - start - len)
        squeeze(head <> requote(quoted) <> strip_dialogue(rest))
    end
  end

  @doc """
  Removes every quoted dialogue span. Used on bridge video_prompts (always
  dialogue-free) and on scene segments after the first, so the one allowed
  line is spoken once per scene, not once per segment.
  """
  def strip_dialogue(prompt), do: prompt |> String.replace(@quoted, "") |> squeeze()

  defp requote(quoted) do
    line = String.trim(quoted, "\"")
    words = line |> String.split() |> Enum.take(@max_dialogue_words)
    "\"" <> Enum.join(words, " ") <> "\""
  end

  defp squeeze(prompt) do
    prompt
    |> String.replace(~r/\s{2,}/, " ")
    |> String.replace(~r/\s+([.,;:!?])/, "\\1")
    |> String.trim()
  end

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

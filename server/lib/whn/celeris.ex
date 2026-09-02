defmodule Whn.Celeris do
  @moduledoc """
  The script engine: one Celeris chat-completions call per beat, returning
  the beat contract (scene summary, bridge, next scene, next choices, state
  updates).

  The request pins the contract with a strict `json_schema` response format;
  parsing still brace-slices, decodes, and clamps every field as defense in
  depth. An invalid or failed reply is retried once, then replaced by a
  canned fallback — this function never raises on model output and a vote
  is never reopened because of it.

  The backend is chosen per call by the SCRIPT_ENGINE env var: "celeris"
  (default) posts to the Celeris API; "gemini" runs Gemini Flash Lite
  through fal's OpenRouter route (no strict schema there — the lenient
  parse carries it). Same prompts, same parsing, swappable for A/B runs.
  """

  alias Whn.Prompts

  @endpoint "https://inference.celeris.ai/celeris-1/v1/chat/completions"

  @fallback_choices [
    "Face the problem head-on",
    "Stall and buy time",
    "Call someone for backup"
  ]

  @doc """
  Runs one script-engine turn for `ctx` (the pipeline ctx map).

  Returns `{:ok, result}` on a valid reply or `{:ok, :fallback, result}`
  after a failed retry. Both video_prompts carry the vertical style suffix.
  """
  @spec run(map()) :: {:ok, map()} | {:ok, :fallback, map()}
  def run(ctx) do
    case attempt(ctx) do
      {:ok, result} ->
        {:ok, finalize(result, ctx.absurdity_level)}

      :error ->
        case attempt(ctx) do
          {:ok, result} -> {:ok, finalize(result, ctx.absurdity_level)}
          :error -> {:ok, :fallback, finalize(fallback(ctx), ctx.absurdity_level)}
        end
    end
  end

  defp attempt(ctx) do
    with {:ok, content} <- post(ctx) do
      parse(content)
    end
  end

  ## HTTP

  defp post(ctx) do
    case System.get_env("SCRIPT_ENGINE", "celeris") do
      "gemini" -> post_gemini(ctx)
      _ -> post_celeris(ctx)
    end
  end

  defp post_gemini(ctx) do
    case Whn.Fal.vision(Prompts.user_prompt(ctx),
           model: "google/gemini-2.5-flash-lite",
           system_prompt: Prompts.system_prompt(),
           temperature: 0.6,
           max_tokens: 700
         ) do
      {:ok, %{output: content}} when is_binary(content) -> {:ok, content}
      _ -> :error
    end
  end

  defp post_celeris(ctx) do
    config = Application.get_env(:whn, :celeris, [])
    url = Keyword.get(config, :url, @endpoint)
    key = System.fetch_env!(Keyword.get(config, :key_env, "CELERIS_KEY"))

    opts =
      [url: url, auth: {:bearer, key}, json: body(ctx)] ++
        Keyword.get(config, :req_options, [])

    case Req.post(opts) do
      {:ok, %Req.Response{status: 200, body: body}} -> content(body)
      _ -> :error
    end
  end

  defp content(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content),
       do: {:ok, content}

  defp content(_body), do: :error

  defp body(ctx) do
    %{
      model: "celeris-1",
      messages: [
        %{role: "system", content: Prompts.system_prompt()},
        %{role: "user", content: Prompts.user_prompt(ctx)}
      ],
      temperature: 0.6,
      max_tokens: 700,
      seed: ctx.seed + ctx.beat,
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "beat", strict: true, schema: schema()}
      }
    }
  end

  defp schema do
    clip = %{
      type: "object",
      properties: %{
        duration: %{type: "integer"},
        script: %{type: "string"},
        video_prompt: %{type: "string"}
      },
      required: ["duration", "script", "video_prompt"]
    }

    %{
      type: "object",
      properties: %{
        scene_summary: %{type: "string"},
        winning_choice: %{type: "string"},
        bridge: clip,
        next_scene: clip,
        next_choices: %{type: "array", items: %{type: "string"}, minItems: 3, maxItems: 3},
        story_state_updates: %{type: "object"}
      },
      required: [
        "scene_summary",
        "winning_choice",
        "bridge",
        "next_scene",
        "next_choices",
        "story_state_updates"
      ]
    }
  end

  ## Parsing — brace-slice, decode, clamp

  defp parse(content) do
    with {:ok, sliced} <- brace_slice(content),
         {:ok, decoded} when is_map(decoded) <- Jason.decode(sliced) do
      clamp(decoded)
    else
      _ -> :error
    end
  end

  defp brace_slice(content) do
    case Regex.run(~r/\{.*\}/s, content) do
      [json] -> {:ok, json}
      nil -> :error
    end
  end

  defp clamp(decoded) do
    with {:ok, bridge} <- clip(decoded["bridge"]),
         {:ok, next_scene} <- clip(decoded["next_scene"]) do
      {:ok,
       %{
         scene_summary: str(decoded["scene_summary"], 600),
         winning_choice: str(decoded["winning_choice"], 200),
         bridge: %{bridge | duration: clamp_duration(bridge.duration)},
         next_scene: %{next_scene | duration: 30},
         next_choices: choices(decoded["next_choices"]),
         story_state_updates: updates(decoded["story_state_updates"])
       }}
    end
  end

  defp clip(%{} = raw) do
    script = str(raw["script"], 1_000)
    video_prompt = str(raw["video_prompt"], 1_000)

    if script == "" or video_prompt == "" do
      :error
    else
      {:ok, %{duration: raw["duration"], script: script, video_prompt: video_prompt}}
    end
  end

  defp clip(_raw), do: :error

  defp clamp_duration(duration) when is_integer(duration), do: max(8, min(12, duration))
  defp clamp_duration(_duration), do: 10

  defp choices(raw) when is_list(raw) do
    kept =
      raw
      |> Enum.map(&str(&1, 120))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.take(3)

    # Backfill skips anything already kept, so a model echoing a fallback
    # string can't reintroduce a duplicate.
    kept ++ Enum.take(@fallback_choices -- kept, 3 - length(kept))
  end

  defp choices(_raw), do: @fallback_choices

  defp updates(raw) when is_map(raw), do: raw
  defp updates(_raw), do: %{}

  defp str(value, max) when is_binary(value), do: value |> String.trim() |> String.slice(0, max)
  defp str(_value, _max), do: ""

  ## Fallback (never reopens the vote, adds no story truth)

  defp fallback(ctx) do
    consequence = ctx.winning_choice || "the situation the premise sets up"

    %{
      scene_summary: "",
      winning_choice: ctx.winning_choice || "",
      bridge: %{
        duration: 10,
        script: "The protagonist takes a breath and commits to the decision.",
        video_prompt:
          "The protagonist reacts, then walks with purpose toward the consequence of: #{consequence}. They come to a stop a few paces away, face readable in even light."
      },
      next_scene: %{
        duration: 30,
        script: "The consequence of the decision plays out and a new complication surfaces.",
        video_prompt:
          "The protagonist deals with the fallout of: #{consequence}, while a new complication arrives mid-scene. The action settles, ending on a stable, well-lit frame."
      },
      next_choices: @fallback_choices,
      story_state_updates: %{}
    }
  end

  # The escalation line is appended after dialogue handling (its single
  # newline must survive the whitespace squeeze) and before the style
  # suffix, which stays the terminal line of every video prompt.
  defp finalize(result, level) do
    result
    |> update_in(
      [:bridge, :video_prompt],
      &(&1 |> Prompts.strip_dialogue() |> escalation(level) |> suffix())
    )
    |> update_in(
      [:next_scene, :video_prompt],
      &(&1 |> Prompts.clamp_dialogue() |> escalation(level) |> suffix())
    )
  end

  defp escalation(video_prompt, level),
    do: video_prompt <> "\nEscalation: " <> Prompts.escalation_fragment(level)

  defp suffix(video_prompt), do: video_prompt <> "\nStyle: " <> Prompts.vertical_suffix()
end

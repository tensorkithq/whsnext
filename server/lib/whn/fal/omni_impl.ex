defmodule Whn.Fal.OmniImpl do
  @moduledoc """
  `Whn.Fal` implementation that generates video on Google's Gemini Omni
  Flash model via fal.ai, selected at runtime with `VIDEO_ENGINE=omni`
  (see `Whn.Fal.video_engine/0`).

  Omni's input schema is narrower than H3 Max's, so inputs are built
  explicitly instead of passed through: no `seed` and no
  `prompt_expansion_mode` (retries re-roll rather than reproduce a clip),
  integer `duration` hard-capped at 10s, resolution pinned to `"360p"`.
  Aspect is pinned to 9:16 on both endpoints — omni does not follow the
  input frame's aspect. Output shape matches H3 Max
  (`video.url`). Non-video operations delegate to the default engine.
  """

  @behaviour Whn.Fal

  @t2v_endpoint "google/gemini-omni-flash/v1.1/text-to-video"
  @i2v_endpoint "google/gemini-omni-flash/v1.1/image-to-video"

  @max_duration 10
  @resolution "360p"

  @impl true
  def t2v(prompt, opts) do
    @t2v_endpoint
    |> FalEx.subscribe(input: t2v_input(prompt, opts))
    |> video_url()
  end

  @impl true
  def i2v(prompt, image_url, opts) do
    @i2v_endpoint
    |> FalEx.subscribe(input: i2v_input(prompt, image_url, opts))
    |> video_url()
  end

  @impl true
  defdelegate flux(prompt, opts), to: Whn.Fal.FalExImpl

  @impl true
  defdelegate vision(prompt, opts), to: Whn.Fal.FalExImpl

  @impl true
  defdelegate upload(path), to: Whn.Fal.FalExImpl

  @doc false
  def t2v_input(prompt, opts) do
    prompt |> base_input(opts) |> Map.put(:aspect_ratio, "9:16")
  end

  @doc false
  def i2v_input(prompt, image_url, opts) do
    prompt
    |> base_input(opts)
    |> Map.put(:image_url, image_url)
    |> Map.put(:aspect_ratio, "9:16")
  end

  defp base_input(prompt, opts) do
    %{prompt: prompt, resolution: @resolution}
    |> put_duration(Keyword.get(opts, :duration))
  end

  defp put_duration(input, nil), do: input

  defp put_duration(input, duration) when is_integer(duration),
    do: Map.put(input, :duration, min(duration, @max_duration))

  defp video_url({:ok, %{"video" => %{"url" => url}}}) when is_binary(url), do: {:ok, %{url: url}}
  defp video_url({:error, reason}), do: {:error, reason}
  defp video_url({:ok, body}), do: {:error, {:unexpected_response, body}}
end

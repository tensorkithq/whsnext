defmodule Whn.Fal.FalExImpl do
  @moduledoc """
  `Whn.Fal` implementation backed by the `fal_ex` package.

  Each call goes through `FalEx.subscribe/2` (queue submit + poll) against a
  fixed endpoint and normalizes the response to the shapes `Whn.Fal` promises.
  Only known model params are forwarded; nil values are dropped.

  Note on the HTTP adapter: fal_ex builds its Tesla clients without naming an
  adapter, which would fall back to Erlang's `:httpc`. It ships hackney as a
  dependency for exactly this purpose, so the app pins
  `config :tesla, adapter: Tesla.Adapter.Hackney` in `config/config.exs`.
  Tesla is used by fal_ex only — hand-written HTTP in this app uses `Req`.
  """

  @behaviour Whn.Fal

  @t2v_endpoint "minimax/h3-max/text-to-video"
  @i2v_endpoint "minimax/h3-max/image-to-video"
  @flux_endpoint "fal-ai/flux-2-pro"
  @vision_endpoint "openrouter/router/vision"

  @passthrough [
    :duration,
    :resolution,
    :aspect_ratio,
    :seed,
    :prompt_expansion_mode,
    :image_url,
    :image_size,
    :model,
    :system_prompt,
    :image_urls,
    :temperature,
    :max_tokens
  ]

  @impl true
  def t2v(prompt, opts) do
    @t2v_endpoint
    |> FalEx.subscribe(input: build_input(prompt, opts))
    |> video_url()
  end

  @impl true
  def i2v(prompt, image_url, opts) do
    @i2v_endpoint
    |> FalEx.subscribe(input: build_input(prompt, Keyword.put(opts, :image_url, image_url)))
    |> video_url()
  end

  @impl true
  def flux(prompt, opts) do
    @flux_endpoint
    |> FalEx.subscribe(input: build_input(prompt, opts))
    |> image_url()
  end

  @impl true
  def vision(prompt, opts) do
    @vision_endpoint
    |> FalEx.subscribe(input: build_input(prompt, opts))
    |> output_text()
  end

  @impl true
  def upload(path) do
    FalEx.storage()
    |> FalEx.Storage.upload(path)
  end

  defp build_input(prompt, opts) do
    opts
    |> Keyword.take(@passthrough)
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.put(:prompt, prompt)
    |> Map.new()
  end

  defp video_url({:ok, %{"video" => %{"url" => url}}}) when is_binary(url), do: {:ok, %{url: url}}
  defp video_url(other), do: unexpected(other)

  defp image_url({:ok, %{"images" => [%{"url" => url} | _]}}) when is_binary(url),
    do: {:ok, %{url: url}}

  defp image_url(other), do: unexpected(other)

  defp output_text({:ok, %{"output" => output}}) when is_binary(output),
    do: {:ok, %{output: output}}

  defp output_text(other), do: unexpected(other)

  defp unexpected({:error, reason}), do: {:error, reason}
  defp unexpected({:ok, body}), do: {:error, {:unexpected_response, body}}
end

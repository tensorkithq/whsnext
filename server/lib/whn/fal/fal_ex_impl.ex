defmodule Whn.Fal.FalExImpl do
  @moduledoc """
  `Whn.Fal` implementation backed by the `fal_ex` package.

  Each call goes through `FalEx.subscribe/2` (queue submit + poll) against a
  fixed endpoint and normalizes the response to the shapes `Whn.Fal` promises.
  Only known model params are forwarded; nil values are dropped.

  Note on the HTTP adapter: fal_ex builds its Tesla clients without naming an
  adapter, which would fall back to Erlang's `:httpc`. It ships hackney as a
  dependency for exactly this purpose, so the app pins the hackney adapter in
  `config/config.exs` with `recv_timeout: 300_000` — hackney's 5s default
  times out mid-generation, while fal_ex's own request timeout is 300s.
  Tesla is used by fal_ex only — hand-written HTTP in this app uses `Req`.

  `upload/1` does not go through fal_ex: its storage client points at a
  host that no longer exists (see the note on the function), so uploads
  use fal's storage REST endpoints via `Req` directly.
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

  # fal_ex's FalEx.Storage targets v3.fal-cdn.com, a host that no longer
  # resolves. Upload through fal's current storage REST flow instead:
  # authenticated initiate call, then a PUT of the bytes to the presigned
  # URL it returns.
  @impl true
  def upload(path) do
    with {:ok, data} <- File.read(path),
         {:ok, %{"file_url" => file_url, "upload_url" => upload_url}} <- initiate_upload(path),
         :ok <- put_upload(upload_url, data, content_type(path)) do
      {:ok, file_url}
    end
  end

  defp initiate_upload(path) do
    case System.get_env("FAL_KEY") do
      nil ->
        {:error, :fal_key_not_set}

      key ->
        "https://rest.alpha.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
        |> Req.post(
          json: %{file_name: Path.basename(path), content_type: content_type(path)},
          headers: [{"authorization", "Key " <> key}]
        )
        |> case do
          {:ok, %Req.Response{status: 200, body: %{"file_url" => _, "upload_url" => _} = body}} ->
            {:ok, body}

          {:ok, %Req.Response{status: status, body: body}} ->
            {:error, {:initiate_upload, status, body}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp put_upload(upload_url, data, content_type) do
    case Req.put(upload_url, body: data, headers: [{"content-type", content_type}]) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:upload_put, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp content_type(path) do
    case path |> Path.extname() |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".mp4" -> "video/mp4"
      _ -> "application/octet-stream"
    end
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

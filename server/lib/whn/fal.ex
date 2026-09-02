defmodule Whn.Fal do
  @moduledoc """
  Boundary for every fal.ai call the app makes.

  Defines the five operations the generation pipeline needs and dispatches
  them to a configured implementation, so the underlying HTTP client can be
  swapped (or stubbed in tests) without touching callers:

      Application.put_env(:whn, :fal_impl, MyStub)

  Defaults to `Whn.Fal.FalExImpl`, which drives the `fal_ex` package.

  Every video/image generation is logged at debug level with its prompt,
  options, wall-clock, and result URL, so `logs` shows exactly what was
  asked of the model and what came back.
  """

  require Logger

  @callback t2v(prompt :: String.t(), opts :: keyword()) ::
              {:ok, %{url: String.t()}} | {:error, term()}
  @callback i2v(prompt :: String.t(), image_url :: String.t(), opts :: keyword()) ::
              {:ok, %{url: String.t()}} | {:error, term()}
  @callback flux(prompt :: String.t(), opts :: keyword()) ::
              {:ok, %{url: String.t()}} | {:error, term()}
  @callback vision(prompt :: String.t(), opts :: keyword()) ::
              {:ok, %{output: String.t()}} | {:error, term()}
  @callback upload(path :: Path.t()) :: {:ok, String.t()} | {:error, term()}

  @doc "Text-to-video. Returns the hosted URL of the generated clip."
  def t2v(prompt, opts \\ []) do
    logged(:t2v, prompt, opts, fn -> impl().t2v(prompt, opts) end)
  end

  @doc "Image-to-video from a hosted first-frame URL. Output aspect follows the image."
  def i2v(prompt, image_url, opts \\ []) do
    logged(:i2v, prompt, [{:image_url, image_url} | opts], fn ->
      impl().i2v(prompt, image_url, opts)
    end)
  end

  @doc "Single still frame from FLUX. Returns the hosted URL of the image."
  def flux(prompt, opts \\ []) do
    logged(:flux, prompt, opts, fn -> impl().flux(prompt, opts) end)
  end

  @doc "One vision-LLM turn. Returns the model's raw text output; callers parse."
  def vision(prompt, opts \\ []), do: impl().vision(prompt, opts)

  @doc "Uploads a local file to fal storage. Returns the hosted URL."
  def upload(path), do: impl().upload(path)

  defp logged(op, prompt, opts, fun) do
    Logger.debug("fal #{op} start opts=#{inspect(Keyword.delete(opts, :prompt))}\n#{prompt}")
    {us, result} = :timer.tc(fun)
    ms = div(us, 1000)

    case result do
      {:ok, %{url: url}} -> Logger.debug("fal #{op} done in #{ms}ms -> #{url}")
      {:error, reason} -> Logger.debug("fal #{op} failed in #{ms}ms: #{inspect(reason)}")
    end

    result
  end

  defp impl, do: Application.get_env(:whn, :fal_impl, Whn.Fal.FalExImpl)
end

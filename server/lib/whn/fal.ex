defmodule Whn.Fal do
  @moduledoc """
  Boundary for every fal.ai call the app makes.

  Defines the five operations the generation pipeline needs and dispatches
  them to a configured implementation, so the underlying HTTP client can be
  swapped (or stubbed in tests) without touching callers:

      Application.put_env(:whn, :fal_impl, MyStub)

  Defaults to `Whn.Fal.FalExImpl`, which drives the `fal_ex` package.
  """

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
  def t2v(prompt, opts \\ []), do: impl().t2v(prompt, opts)

  @doc "Image-to-video from a hosted first-frame URL. Output aspect follows the image."
  def i2v(prompt, image_url, opts \\ []), do: impl().i2v(prompt, image_url, opts)

  @doc "Single still frame from FLUX. Returns the hosted URL of the image."
  def flux(prompt, opts \\ []), do: impl().flux(prompt, opts)

  @doc "One vision-LLM turn. Returns the model's raw text output; callers parse."
  def vision(prompt, opts \\ []), do: impl().vision(prompt, opts)

  @doc "Uploads a local file to fal storage. Returns the hosted URL."
  def upload(path), do: impl().upload(path)

  defp impl, do: Application.get_env(:whn, :fal_impl, Whn.Fal.FalExImpl)
end

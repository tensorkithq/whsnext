# Timed fal spike — measures the generation wall-clock the README §2 timing
# model assumes, and validates the FLUX 720x1280 custom size, hosted-URL
# image_url acceptance on i2v, and image-attached vision calls.
#
# Run once (costs real money — two 10s 480P clips + a FLUX frame + one
# vision call, roughly $0.50–$1.10):
#
#     cd server && mix run scripts/fal_spike.exs

unless System.get_env("FAL_KEY") do
  IO.puts(:stderr, """
  FAL_KEY is not set. Put it in .env at the repo root (see .env.example)
  and re-enter the devshell so the shellHook sources it.
  """)

  System.halt(1)
end

defmodule Whn.Scripts.FalSpike do
  @doc "Times one stage, prints its wall-clock, unwraps ok/error."
  def stage(name, fun) do
    {us, result} = :timer.tc(fun)
    ms = div(us, 1000)
    IO.puts("STAGE #{name} #{ms}ms")

    case result do
      {:ok, value} -> {ms, value}
      {:error, reason} -> raise "stage #{name} failed: #{inspect(reason)}"
    end
  end
end

alias Whn.Scripts.FalSpike

total_start = System.monotonic_time(:millisecond)

# 1. FLUX opening frame at the vertical 720x1280 the episode plays at.
{_flux_ms, %{url: flux_url}} =
  FalSpike.stage("flux", fn ->
    Whn.Fal.flux(
      "Lagos street at golden hour, young Nigerian man in his twenties " <>
        "checking his phone, warm low sun, bustling market behind him, " <>
        "vertical composition",
      image_size: %{width: 720, height: 1280},
      seed: 42
    )
  end)

IO.puts("  flux frame: #{flux_url}")

# 2. i2v from the HOSTED flux URL — validates hosted-URL acceptance (no data URI).
{i2v_ms, %{url: i2v_url}} =
  FalSpike.stage("i2v", fn ->
    Whn.Fal.i2v(
      "He looks up from the phone and breaks into a grin as street life " <>
        "flows around him",
      flux_url,
      duration: 10,
      resolution: "480P",
      prompt_expansion_mode: "disabled",
      seed: 42
    )
  end)

IO.puts("  i2v clip: #{i2v_url}")

# 3. Full last-frame round-trip: download + ffmpeg extract + storage upload.
{_frame_ms, last_frame_url} =
  FalSpike.stage("last_frame", fn -> Whn.Frames.last_frame(i2v_url) end)

IO.puts("  last frame: #{last_frame_url}")

# 4. Cold-start t2v at the same duration/resolution the episode uses.
{_t2v_ms, %{url: t2v_url}} =
  FalSpike.stage("t2v", fn ->
    Whn.Fal.t2v(
      "Vertical video: a yellow Lagos danfo bus pulls up on a busy street " <>
        "at golden hour, conductor leaning out of the door calling for " <>
        "passengers",
      duration: 10,
      resolution: "480P",
      aspect_ratio: "9:16",
      prompt_expansion_mode: "balanced",
      seed: 42
    )
  end)

IO.puts("  t2v clip: #{t2v_url}")

# 5. Vision turn with the extracted frame attached — validates image-attached calls.
{_vision_ms, %{output: vision_output}} =
  FalSpike.stage("vision", fn ->
    Whn.Fal.vision(
      ~s(Describe this frame in one sentence. ) <>
        ~s(Reply as JSON: {"description": "<one sentence>"}),
      model: "google/gemini-2.5-flash-lite",
      image_urls: [last_frame_url],
      temperature: 0.6,
      max_tokens: 700
    )
  end)

IO.puts("  vision output: #{vision_output}")

total_ms = System.monotonic_time(:millisecond) - total_start
IO.puts("TOTAL #{total_ms}ms")

budget_ms = 20_000
verdict = if i2v_ms <= budget_ms, do: "within budget", else: "OVER BUDGET"

IO.puts(
  "BUDGET CHECK i2v #{i2v_ms}ms vs #{budget_ms}ms remaining-scene+bridge " <>
    "playback budget — #{verdict}"
)

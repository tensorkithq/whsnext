defmodule Whn.Pipeline do
  @moduledoc """
  Winner-only generation cycle, run as a supervised task per beat.

  A cycle is: Celeris script → bridge clip out of the vote → last-frame
  extraction → three chained 10s scene segments, each seeding the next via
  its final frame. The opening replaces the bridge with a FLUX still built
  from the premise. Every stage reports to `dest` as a `{:pipeline, beat,
  message}` send; the destination applies its own stale-beat guard.

  After the final segment is delivered, the cycle extracts that segment's
  last frame — best-effort — and reports it as `{:last_frame, url}` so the
  next cycle's bridge can animate from the scene's end.

  Each generation stage gets one retry with identical arguments — the seed
  makes the request idempotent — before the cycle stops with an error
  message. Per-stage timeouts are 3x the wall-clock measured in the fal
  timing spike.

  Under `VIDEO_ENGINE=omni` (see `Whn.Fal.video_engine/0`) the clip plan
  changes: the bridge becomes 15s as two chained clips (10s, then 5s from
  its last frame), and the three scene segments generate in parallel from
  one shared anchor frame instead of chaining — the "part n of 3" prompt
  suffix carries continuity. Omni ignores seeds, so its retries re-roll.
  """

  @callback start_opening(dest :: pid(), ctx :: map()) :: {:ok, pid()} | {:error, term()}
  @callback start_cycle(dest :: pid(), ctx :: map()) :: {:ok, pid()} | {:error, term()}

  @behaviour __MODULE__

  require Logger

  # 3x measured wall-clock: flux 12.1s, i2v 4.9s / t2v 5.3s, frame trip 2.9s.
  @flux_timeout 36_500
  @video_timeout 16_000
  @frame_timeout 9_000
  # omni measures ~34s per 10s clip; same 3x headroom
  @omni_video_timeout 105_000

  @impl true
  def start_opening(dest, ctx) do
    Task.Supervisor.start_child(Whn.TaskSupervisor, fn -> run_opening(dest, ctx) end)
  end

  @impl true
  def start_cycle(dest, ctx) do
    Task.Supervisor.start_child(Whn.TaskSupervisor, fn -> run_cycle(dest, ctx) end)
  end

  defp run_cycle(dest, ctx) do
    Process.flag(:trap_exit, true)
    seed = ctx.seed + ctx.beat

    result = script(ctx)
    notify(dest, ctx.beat, {:celeris, result})

    outcome =
      with {:ok, frame_url} <- run_bridge(dest, ctx, result.bridge.video_prompt, seed) do
        run_segments(dest, ctx.beat, result.next_scene.video_prompt, frame_url, seed)
      end

    chain_frame(outcome, dest, ctx.beat)
    report(outcome, dest, ctx.beat)
  end

  defp run_opening(dest, ctx) do
    Process.flag(:trap_exit, true)
    seed = ctx.seed + ctx.beat

    result = ctx |> script() |> Map.put(:bridge, nil)
    notify(dest, ctx.beat, {:celeris, result})

    outcome =
      with {:ok, %{url: image_url}} <-
             with_retry(:frame, @flux_timeout, fn ->
               Whn.Fal.flux(opening_prompt(ctx),
                 image_size: %{width: 720, height: 1280},
                 seed: ctx.seed
               )
             end) do
        run_segments(dest, ctx.beat, result.next_scene.video_prompt, image_url, seed)
      end

    chain_frame(outcome, dest, ctx.beat)
    report(outcome, dest, ctx.beat)
  end

  defp script(ctx) do
    case Whn.Celeris.run(ctx) do
      {:ok, result} -> result
      {:ok, :fallback, result} -> result
    end
  end

  defp opening_prompt(ctx) do
    "Opening frame: #{ctx.episode.premise} #{Whn.Prompts.vertical_suffix()}"
  end

  defp run_bridge(dest, ctx, prompt, seed) do
    case Whn.Fal.video_engine() do
      :default -> run_single_bridge(dest, ctx, prompt, seed)
      :omni -> run_omni_bridge(dest, ctx, prompt, seed)
    end
  end

  defp run_single_bridge(dest, ctx, prompt, seed) do
    with {:ok, %{url: bridge_url}} <- bridge_clip(ctx, prompt, seed),
         :ok <- notify(dest, ctx.beat, {:bridge_ready, bridge_url}) do
      extract_frame(bridge_url)
    end
  end

  # Omni plays the bridge as 15s: a 10s clip, then a 5s clip animated from
  # its last frame. Each lands as its own bridge_ready; the EpisodeServer
  # extends the pending bridge entry rather than queueing a second playback.
  defp run_omni_bridge(dest, ctx, prompt, seed) do
    with {:ok, %{url: first_url}} <- bridge_clip(ctx, prompt, seed),
         :ok <- notify(dest, ctx.beat, {:bridge_ready, first_url}),
         {:ok, mid_frame} <- extract_frame(first_url),
         {:ok, %{url: second_url}} <-
           with_retry(:bridge, video_timeout(), fn -> i2v(prompt, mid_frame, seed, 5) end),
         :ok <- notify(dest, ctx.beat, {:bridge_ready, second_url}) do
      extract_frame(second_url)
    end
  end

  defp bridge_clip(%{last_frame_url: nil}, prompt, seed) do
    with_retry(:bridge, video_timeout(), fn ->
      Whn.Fal.t2v(prompt,
        duration: 10,
        resolution: "480P",
        aspect_ratio: "9:16",
        prompt_expansion_mode: "balanced",
        seed: seed
      )
    end)
  end

  defp bridge_clip(%{last_frame_url: frame_url}, prompt, seed) do
    with_retry(:bridge, video_timeout(), fn -> i2v(prompt, frame_url, seed) end)
  end

  defp run_segments(dest, beat, video_prompt, frame_url, seed) do
    case Whn.Fal.video_engine() do
      :default -> run_chained_segments(dest, beat, video_prompt, frame_url, seed)
      :omni -> run_parallel_segments(dest, beat, video_prompt, frame_url, seed)
    end
  end

  defp run_chained_segments(dest, beat, video_prompt, frame_url, seed) do
    Enum.reduce_while(0..2, {:ok, frame_url}, fn idx, {:ok, frame} ->
      prompt = segment_prompt(video_prompt, idx)

      with {:ok, %{url: url}} <-
             with_retry(:segment, video_timeout(), fn -> i2v(prompt, frame, seed) end),
           :ok <- notify(dest, beat, {:segment_ready, idx, url}),
           {:ok, next_frame} <- next_frame(idx, url) do
        {:cont, {:ok, next_frame}}
      else
        error -> {:halt, error}
      end
    end)
  end

  # Omni fan-out: all three segments animate in parallel from the same
  # anchor frame — no chaining, the prompt suffix carries continuity.
  # Results are consumed in stream order, so segment_ready still arrives
  # as 0, 1, 2 even when a later clip finishes first.
  defp run_parallel_segments(dest, beat, video_prompt, frame_url, seed) do
    timeout = video_timeout()

    0..2
    |> Task.async_stream(
      fn idx ->
        Process.flag(:trap_exit, true)
        prompt = segment_prompt(video_prompt, idx)
        with_retry(:segment, timeout, fn -> i2v(prompt, frame_url, seed) end)
      end,
      max_concurrency: 3,
      timeout: :infinity
    )
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, nil}, fn {{:ok, result}, idx}, {:ok, _prev} ->
      case result do
        {:ok, %{url: url}} ->
          notify(dest, beat, {:segment_ready, idx, url})
          # consumed in order, so the final accumulator is segment 2's url —
          # chain_frame extracts the scene-end frame from it, same as chained
          {:cont, {:ok, url}}

        error ->
          {:halt, error}
      end
    end)
  end

  # The one allowed dialogue line is spoken once per scene: segments after
  # the first drop any quoted speech from the shared prompt (both engines).
  defp segment_prompt(video_prompt, 0), do: "#{video_prompt} Continuation, part 1 of 3."

  defp segment_prompt(video_prompt, idx) do
    "#{Whn.Prompts.strip_dialogue(video_prompt)} Continuation, part #{idx + 1} of 3."
  end

  defp i2v(prompt, image_url, seed, duration \\ 10) do
    Whn.Fal.i2v(prompt, image_url,
      duration: duration,
      resolution: "480P",
      prompt_expansion_mode: "disabled",
      seed: seed
    )
  end

  defp video_timeout do
    case Whn.Fal.video_engine() do
      :omni -> @omni_video_timeout
      :default -> @video_timeout
    end
  end

  # the final segment's own extraction is skipped inside the loop, but its
  # url flows out so the cycle can chain its end frame after delivery
  defp next_frame(2, url), do: {:ok, url}
  defp next_frame(_idx, url), do: extract_frame(url)

  defp extract_frame(video_url) do
    with_retry(:frame, @frame_timeout, fn -> Whn.Frames.last_frame(video_url) end)
  end

  # Scene-end chaining is best-effort: the scene is already delivered when
  # this runs, so a failure logs and skips — it must never surface as
  # {:error, :frame, _} and flip a playable episode to hold. Single attempt,
  # no retry: the next bridge falls back to t2v exactly as before.
  defp chain_frame({:ok, last_url}, dest, beat) when is_binary(last_url) do
    case Whn.Frames.last_frame(last_url) do
      {:ok, frame_url} ->
        notify(dest, beat, {:last_frame, frame_url})

      {:error, reason} ->
        Logger.warning("scene-end frame extraction failed for beat #{beat}: #{inspect(reason)}")
    end
  end

  defp chain_frame(_error_or_nil, _dest, _beat), do: :ok

  defp report({:error, stage, reason}, dest, beat) do
    notify(dest, beat, {:error, stage, reason})
  end

  defp report(_ok, _dest, _beat), do: :ok

  defp notify(dest, beat, message) do
    send(dest, {:pipeline, beat, message})
    :ok
  end

  ## Retry — once, with identical arguments (same seed keeps it idempotent)

  defp with_retry(stage, timeout, fun) do
    case attempt(fun, timeout) do
      {:error, _first_failure} ->
        case attempt(fun, timeout) do
          {:error, reason} -> {:error, stage, reason}
          ok -> ok
        end

      ok ->
        ok
    end
  end

  defp attempt(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, _value} = ok} -> ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, other} -> {:error, {:unexpected_return, other}}
      {:exit, reason} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end
end

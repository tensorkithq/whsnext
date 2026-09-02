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
  """

  @callback start_opening(dest :: pid(), ctx :: map()) :: {:ok, pid()} | {:error, term()}
  @callback start_cycle(dest :: pid(), ctx :: map()) :: {:ok, pid()} | {:error, term()}

  @behaviour __MODULE__

  require Logger

  # 3x measured wall-clock: flux 12.1s, i2v 4.9s / t2v 5.3s, frame trip 2.9s.
  @flux_timeout 36_500
  @video_timeout 16_000
  @frame_timeout 9_000

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
      with {:ok, %{url: bridge_url}} <- bridge_clip(ctx, result.bridge.video_prompt, seed),
           :ok <- notify(dest, ctx.beat, {:bridge_ready, bridge_url}),
           {:ok, frame_url} <- extract_frame(bridge_url) do
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

  defp bridge_clip(%{last_frame_url: nil}, prompt, seed) do
    with_retry(:bridge, @video_timeout, fn ->
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
    with_retry(:bridge, @video_timeout, fn -> i2v(prompt, frame_url, seed) end)
  end

  defp run_segments(dest, beat, video_prompt, frame_url, seed) do
    Enum.reduce_while(0..2, {:ok, frame_url}, fn idx, {:ok, frame} ->
      # Prompts arrive dialogue-free from the script engine; stripping
      # again here is a harmless belt-and-braces pass per segment.
      base = if idx == 0, do: video_prompt, else: Whn.Prompts.strip_dialogue(video_prompt)
      prompt = "#{base} Continuation, part #{idx + 1} of 3."

      with {:ok, %{url: url}} <-
             with_retry(:segment, @video_timeout, fn -> i2v(prompt, frame, seed) end),
           :ok <- notify(dest, beat, {:segment_ready, idx, url}),
           {:ok, next_frame} <- next_frame(idx, url) do
        {:cont, {:ok, next_frame}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp i2v(prompt, image_url, seed) do
    Whn.Fal.i2v(prompt, image_url,
      duration: 10,
      resolution: "480P",
      prompt_expansion_mode: "disabled",
      seed: seed
    )
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

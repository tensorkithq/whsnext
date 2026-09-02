defmodule Whn.EpisodeServer do
  @moduledoc """
  One live episode: phases, playback, the vote window, and the server-owned
  clocks. Every transition is an explicit `{:timeline, event}` self-message
  scheduled with `Process.send_after`, so tests drive them manually.

  Generation is delegated to the configured pipeline (`:pipeline_impl`),
  which reports back with `{:pipeline, beat, message}` sends. Messages for
  any beat other than the current one are stale and dropped.

  A vote only becomes canon with at least `min_voters` distinct voters
  (default 2). A smaller turnout closes the poll without a winner and
  re-offers the same choices later instead of spending on generation —
  a lone idle tab must never keep the burner on.

  All `*_ms` fields in broadcast payloads are absolute epoch milliseconds.
  """

  use GenServer

  require Logger

  @topic "episode:live"
  @vote_question "What happens next?"

  @default_timings %{
    vote_open_ms: 10_000,
    vote_window_ms: 10_000,
    segment_ms: 10_000,
    presence_check_ms: 3_000,
    revote_ms: 15_000,
    reveal_ms: 2_500
  }

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs, name: via(Map.fetch!(attrs, :id)))
  end

  defp via(id), do: {:via, Registry, {Whn.EpisodeRegistry, id}}

  @doc "Full EpisodeSync map for a joining client, personalized by anon_id."
  def join_sync(pid, anon_id), do: GenServer.call(pid, {:join_sync, anon_id})

  @doc "Casts a vote. First write wins; duplicates reply ok with the original pick."
  def vote(pid, anon_id, option_idx), do: GenServer.call(pid, {:vote, anon_id, option_idx})

  @impl true
  def init(attrs) do
    {:ok, _} = Registry.register(Whn.EpisodeRegistry, :current, Map.fetch!(attrs, :id))

    timings = Map.merge(@default_timings, Map.get(attrs, :timings, %{}))

    state = %{
      id: Map.fetch!(attrs, :id),
      episode_id: Map.get(attrs, :episode_id),
      title: Map.fetch!(attrs, :title),
      premise: Map.fetch!(attrs, :premise),
      seed: Map.get(attrs, :seed, Enum.random(0..2_147_483_646)),
      phase: "idle",
      beat: 0,
      absurdity_level: 0,
      playback: nil,
      pending_segments: [],
      vote: nil,
      votes: %{},
      current_decision_id: nil,
      scene_urls: [],
      timings: timings,
      story_state: Map.get(attrs, :story_state, %{}),
      history: [],
      last_frame_url: nil,
      durations: nil,
      next_choices: nil,
      opening_started: false,
      pending_cycle: nil,
      min_voters: Map.get(attrs, :min_voters, 2),
      viewer_count_fn: Map.get(attrs, :viewer_count_fn, &default_viewer_count/0)
    }

    schedule(:presence_check, timings.presence_check_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:join_sync, anon_id}, _from, state) do
    sync = %{
      phase: state.phase,
      episode: %{title: state.title, premise: state.premise},
      now_ms: now_ms(),
      playback: state.playback,
      vote: sync_vote(state, anon_id)
    }

    {:reply, sync, state}
  end

  def handle_call({:vote, anon_id, option_idx}, _from, state) do
    case check_vote(state, option_idx) do
      :ok ->
        votes = Map.put_new(state.votes, anon_id, option_idx)
        accepted? = map_size(votes) > map_size(state.votes)
        tallies = tally(votes, length(state.vote.options))

        if accepted? do
          broadcast("vote_update", %{tallies: tallies})
          persist_vote(state, anon_id, option_idx)
        end

        state = %{state | votes: votes, vote: %{state.vote | tallies: tallies}}
        {:reply, {:ok, %{tallies: tallies, your_vote: Map.fetch!(votes, anon_id)}}, state}

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:timeline, event}, state), do: {:noreply, handle_timeline(event, state)}

  # Scene-end frames are latest ground truth, not per-beat artifacts: the
  # trailing extraction can straddle the lock's beat bump, so this head is
  # exempt from the stale-beat guard below. Latest write wins.
  def handle_info({:pipeline, _beat, {:last_frame, url}}, state) do
    {:noreply, %{state | last_frame_url: url}}
  end

  def handle_info({:pipeline, beat, message}, %{beat: beat} = state) do
    {:noreply, handle_pipeline(message, state)}
  end

  def handle_info({:pipeline, _stale_beat, _message}, state), do: {:noreply, state}

  ## Timeline

  defp handle_timeline(:presence_check, state) do
    cond do
      not state.opening_started ->
        if state.viewer_count_fn.() >= 1 do
          dispatch(:start_opening, pipeline_ctx(state, nil))
          set_phase(%{state | opening_started: true}, "opening")
        else
          schedule(:presence_check, state.timings.presence_check_ms)
          state
        end

      state.pending_cycle != nil ->
        if state.viewer_count_fn.() >= 1 do
          # The ctx snapshot was taken at lock; a frame extracted during the
          # hold would otherwise be silently unused. Refresh at dispatch.
          dispatch(:start_cycle, %{state.pending_cycle | last_frame_url: state.last_frame_url})
          %{state | pending_cycle: nil}
        else
          schedule(:presence_check, state.timings.presence_check_ms)
          state
        end

      true ->
        state
    end
  end

  defp handle_timeline(:vote_open, %{next_choices: [_ | _] = choices} = state) do
    vote = %{
      question: @vote_question,
      options: choices,
      tallies: List.duplicate(0, length(choices)),
      deadline_ms: now_ms() + state.timings.vote_window_ms,
      locked: false,
      winner_idx: nil,
      your_vote: nil
    }

    decision_id = persist_decision(state, vote)
    broadcast("vote_open", vote)
    schedule(:vote_lock, state.timings.vote_window_ms)
    %{state | vote: vote, votes: %{}, next_choices: nil, current_decision_id: decision_id}
  end

  defp handle_timeline(:vote_open, state), do: state

  defp handle_timeline(:vote_lock, %{vote: %{locked: false} = vote} = state) do
    if map_size(state.votes) >= state.min_voters do
      lock_and_start_cycle(vote, state)
    else
      # Not enough voters to canonize a choice: close the poll without a
      # winner and re-offer the same options later. No generation happens.
      broadcast("vote_closed", %{})
      schedule(:revote, state.timings.revote_ms)
      %{state | vote: nil, votes: %{}, next_choices: vote.options}
    end
  end

  defp handle_timeline(:vote_lock, state), do: state

  # The reveal window: a quorum lock schedules this instead of closing
  # inline, so the winner stays on screen. Only a still-locked vote is
  # closeable — a consumed close leaves vote nil and a reopened poll is
  # locked: false, so a stale event falls through.
  defp handle_timeline(:vote_close, %{vote: %{locked: true}} = state) do
    broadcast("vote_closed", %{})
    %{state | vote: nil}
  end

  defp handle_timeline(:vote_close, state), do: state

  defp handle_timeline(:revote, %{vote: nil, next_choices: [_ | _]} = state) do
    if state.viewer_count_fn.() >= 1 do
      handle_timeline(:vote_open, state)
    else
      schedule(:revote, state.timings.revote_ms)
      state
    end
  end

  defp handle_timeline(:revote, state), do: state

  defp handle_timeline(:scene_boundary, state), do: advance(state)

  defp lock_and_start_cycle(vote, state) do
    tallies = tally(state.votes, length(vote.options))

    {_count, winner_idx} =
      tallies |> Enum.with_index() |> Enum.max_by(fn {count, _idx} -> count end)

    broadcast("vote_locked", %{winner_idx: winner_idx, tallies: tallies})
    schedule(:vote_close, state.timings.reveal_ms)
    persist_finalize(state, tallies, winner_idx)

    state = %{
      state
      | vote: %{vote | locked: true, winner_idx: winner_idx, tallies: tallies},
        beat: state.beat + 1,
        absurdity_level: state.absurdity_level + 1,
        scene_urls: []
    }

    ctx = pipeline_ctx(state, Enum.at(vote.options, winner_idx))

    if state.viewer_count_fn.() >= 1 do
      dispatch(:start_cycle, ctx)
      state
    else
      schedule(:presence_check, state.timings.presence_check_ms)
      set_phase(%{state | pending_cycle: ctx}, "hold")
    end
  end

  ## Pipeline messages (already beat-guarded)

  defp handle_pipeline({:celeris, result}, state) do
    history =
      case Map.get(result, :scene_summary) do
        summary when is_binary(summary) and summary != "" -> state.history ++ [summary]
        _ -> state.history
      end

    story_state =
      Map.merge(state.story_state, Map.get(result, :story_state_updates) || %{})

    persist_story_state(state, story_state)

    %{
      state
      | next_choices: Map.get(result, :next_choices),
        durations: %{
          bridge: get_in(result, [:bridge, :duration]),
          next_scene: get_in(result, [:next_scene, :duration])
        },
        story_state: story_state,
        history: history
    }
  end

  defp handle_pipeline({:bridge_ready, url}, state) do
    persist_beat(state, "bridge", [url])
    entry = %{kind: "bridge", beat: state.beat, segments: [url]}
    %{state | pending_segments: state.pending_segments ++ [entry]}
  end

  defp handle_pipeline({:segment_ready, _idx, url}, state) do
    state = %{state | scene_urls: state.scene_urls ++ [url]}
    persist_beat(state, "scene", state.scene_urls)
    state = append_segment(state, url)
    broadcast("preload", %{urls: pending_urls(state)})
    maybe_promote(state)
  end

  defp handle_pipeline({:error, stage, reason}, state) do
    Logger.error("pipeline error in #{stage} for beat #{state.beat}: #{inspect(reason)}")
    if state.playback == nil, do: set_phase(state, "hold"), else: state
  end

  ## Playback queue

  defp append_segment(state, url) do
    beat = state.beat

    case List.last(state.pending_segments) do
      %{kind: "scene", beat: ^beat} = entry ->
        updated = %{entry | segments: entry.segments ++ [url]}
        %{state | pending_segments: List.replace_at(state.pending_segments, -1, updated)}

      _ ->
        entry = %{kind: "scene", beat: beat, segments: [url]}
        %{state | pending_segments: state.pending_segments ++ [entry]}
    end
  end

  defp maybe_promote(%{playback: nil, phase: phase} = state) when phase in ["hold", "opening"] do
    advance(state)
  end

  defp maybe_promote(state), do: state

  defp advance(%{pending_segments: [entry | rest]} = state) do
    playback = %{
      kind: entry.kind,
      beat: entry.beat,
      segments: entry.segments,
      started_at_ms: now_ms()
    }

    broadcast("playback", playback)
    schedule(:scene_boundary, length(entry.segments) * state.timings.segment_ms)
    if entry.kind == "scene", do: schedule(:vote_open, state.timings.vote_open_ms)

    set_phase(%{state | playback: playback, pending_segments: rest}, "live")
  end

  defp advance(%{pending_segments: []} = state) do
    set_phase(%{state | playback: nil}, "hold")
  end

  ## Voting

  defp check_vote(%{vote: nil}, _idx), do: {:error, :no_open_vote}
  defp check_vote(%{vote: %{locked: true}}, _idx), do: {:error, :locked}

  defp check_vote(%{vote: %{options: options}}, idx)
       when is_integer(idx) and idx >= 0 and idx < length(options),
       do: :ok

  defp check_vote(_state, _out_of_range_idx), do: {:error, :no_open_vote}

  defp tally(votes, option_count) do
    frequencies = Enum.frequencies(Map.values(votes))
    for idx <- 0..(option_count - 1)//1, do: Map.get(frequencies, idx, 0)
  end

  defp sync_vote(%{vote: nil}, _anon_id), do: nil
  defp sync_vote(%{vote: %{locked: true}}, _anon_id), do: nil

  defp sync_vote(state, anon_id) do
    %{state.vote | your_vote: Map.get(state.votes, anon_id)}
  end

  ## Persistence
  #
  # Opening and finalizing a decision are synchronous boundary writes; every
  # other write is fire-and-forget so the episode mailbox never waits on the
  # database. An episode without a database row (started directly in tests)
  # skips persistence entirely.

  defp persist_decision(%{episode_id: nil}, _vote), do: nil

  defp persist_decision(state, vote) do
    {:ok, decision} =
      Whn.Store.record_decision(state.episode_id, %{
        beat_idx: state.beat,
        question: vote.question,
        options: vote.options,
        tallies: vote.tallies,
        deadline_ms: vote.deadline_ms
      })

    decision.id
  end

  defp persist_finalize(%{current_decision_id: nil}, _tallies, _winner_idx), do: :ok

  defp persist_finalize(state, tallies, winner_idx) do
    {:ok, _} = Whn.Store.finalize_decision(state.current_decision_id, tallies, winner_idx)
    :ok
  end

  defp persist_vote(%{current_decision_id: nil}, _anon_id, _option_idx), do: :ok

  defp persist_vote(state, anon_id, option_idx) do
    decision_id = state.current_decision_id

    {:ok, _} =
      Task.Supervisor.start_child(Whn.TaskSupervisor, fn ->
        Whn.Store.record_vote(decision_id, anon_id, option_idx)
      end)

    :ok
  end

  defp persist_story_state(%{episode_id: nil}, _story_state), do: :ok

  defp persist_story_state(state, story_state) do
    episode_id = state.episode_id

    {:ok, _} =
      Task.Supervisor.start_child(Whn.TaskSupervisor, fn ->
        Whn.Store.update_story_state(episode_id, story_state)
      end)

    :ok
  end

  defp persist_beat(%{episode_id: nil}, _kind, _segments), do: :ok

  defp persist_beat(state, kind, segments) do
    episode_id = state.episode_id

    attrs = %{
      idx: state.beat,
      kind: kind,
      segments: segments,
      meta: %{"seed" => state.seed + state.beat}
    }

    {:ok, _} =
      Task.Supervisor.start_child(Whn.TaskSupervisor, fn ->
        Whn.Store.upsert_beat(episode_id, attrs)
      end)

    :ok
  end

  ## Helpers

  defp pipeline_ctx(state, winning_choice) do
    %{
      beat: state.beat,
      seed: state.seed,
      episode: %{title: state.title, premise: state.premise},
      story_state: state.story_state,
      winning_choice: winning_choice,
      last_frame_url: state.last_frame_url,
      history: state.history,
      absurdity_level: state.absurdity_level
    }
  end

  defp dispatch(fun, ctx) do
    case apply(pipeline_impl(), fun, [self(), ctx]) do
      {:ok, _pid} -> :ok
      {:error, reason} -> Logger.error("pipeline #{fun} failed to start: #{inspect(reason)}")
    end
  end

  defp pipeline_impl, do: Application.get_env(:whn, :pipeline_impl, Whn.Pipeline)

  defp default_viewer_count, do: map_size(WhnWeb.Presence.list(@topic))

  defp set_phase(%{phase: phase} = state, phase), do: state

  defp set_phase(state, phase) do
    broadcast("phase", %{phase: phase})
    %{state | phase: phase}
  end

  defp pending_urls(state), do: Enum.flat_map(state.pending_segments, & &1.segments)

  defp broadcast(event, payload), do: WhnWeb.Endpoint.broadcast(@topic, event, payload)

  defp schedule(event, ms), do: Process.send_after(self(), {:timeline, event}, ms)

  defp now_ms, do: System.system_time(:millisecond)
end

defmodule Whn.EpisodeServerTest do
  use ExUnit.Case, async: false

  alias Phoenix.Socket.Broadcast

  @celeris %{
    scene_summary: "Ade sees the salary alert",
    winning_choice: nil,
    bridge: nil,
    next_scene: %{duration: 30, script: "beat script", video_prompt: "beat prompt"},
    next_choices: ["Confront the boss", "Hide the alert", "Call Mama"],
    story_state_updates: %{money: "just paid"}
  }

  setup do
    Application.put_env(:whn, :pipeline_impl, Whn.PipelineStub)
    on_exit(fn -> Application.delete_env(:whn, :pipeline_impl) end)
    start_supervised!(Whn.PipelineStub)
    Phoenix.PubSub.subscribe(Whn.PubSub, "episode:live")
    :ok
  end

  defp start_episode(attrs \\ %{}) do
    defaults = %{
      id: "ep-test",
      title: "Salary Just Entered",
      premise: "Lagos wahala",
      seed: 7,
      viewer_count_fn: fn -> 1 end
    }

    start_supervised!({Whn.EpisodeServer, Map.merge(defaults, attrs)})
  end

  defp open_vote(pid) do
    send(pid, {:pipeline, 0, {:celeris, @celeris}})
    send(pid, {:timeline, :vote_open})
    _ = :sys.get_state(pid)
  end

  # EP-05
  test "vote opens with the window deadline, locks to the lowest tied index" do
    pid = start_episode()
    open_vote(pid)

    assert_receive %Broadcast{event: "vote_open", payload: open}
    assert open.options == ["Confront the boss", "Hide the alert", "Call Mama"]
    assert open.tallies == [0, 0, 0]
    refute open.locked
    assert open.winner_idx == nil

    assert {:ok, %{tallies: [0, 1, 0], your_vote: 1}} = Whn.EpisodeServer.vote(pid, "a1", 1)
    assert_receive %Broadcast{event: "vote_update", payload: %{tallies: [0, 1, 0]}}
    assert {:ok, %{tallies: [0, 1, 1], your_vote: 2}} = Whn.EpisodeServer.vote(pid, "a2", 2)
    assert {:ok, %{tallies: [0, 2, 1], your_vote: 1}} = Whn.EpisodeServer.vote(pid, "a3", 1)
    assert {:ok, %{tallies: [0, 2, 2], your_vote: 2}} = Whn.EpisodeServer.vote(pid, "a4", 2)

    send(pid, {:timeline, :vote_lock})

    assert_receive %Broadcast{event: "vote_locked", payload: %{winner_idx: 1, tallies: [0, 2, 2]}}
    assert_receive %Broadcast{event: "vote_closed", payload: %{}}

    assert [{:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.winning_choice == "Hide the alert"
    assert ctx.beat == 1
  end

  # D-01 at the server boundary
  test "votes are immutable: duplicate vote replies ok with the original pick" do
    pid = start_episode()
    open_vote(pid)
    assert_receive %Broadcast{event: "vote_open"}

    assert {:ok, %{tallies: [1, 0, 0], your_vote: 0}} = Whn.EpisodeServer.vote(pid, "a1", 0)
    assert_receive %Broadcast{event: "vote_update", payload: %{tallies: [1, 0, 0]}}

    assert {:ok, %{tallies: [1, 0, 0], your_vote: 0}} = Whn.EpisodeServer.vote(pid, "a1", 2)
    refute_receive %Broadcast{event: "vote_update"}
  end

  test "vote without an open vote replies no_open_vote; after lock replies locked" do
    pid = start_episode()
    assert {:error, :no_open_vote} = Whn.EpisodeServer.vote(pid, "a1", 0)

    open_vote(pid)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)
    assert {:error, :locked} = Whn.EpisodeServer.vote(pid, "a1", 0)
  end

  # EP-06
  test "boundary with nothing ready holds; segment_ready resumes playback" do
    pid = start_episode()
    send(pid, {:timeline, :scene_boundary})
    assert_receive %Broadcast{event: "phase", payload: %{phase: "hold"}}
    assert :sys.get_state(pid).phase == "hold"

    url = "https://cdn.fal.example/seg0.mp4"
    send(pid, {:pipeline, 0, {:segment_ready, 0, url}})

    assert_receive %Broadcast{event: "preload", payload: %{urls: [^url]}}
    assert_receive %Broadcast{event: "playback", payload: playback}
    assert playback.kind == "scene"
    assert playback.beat == 0
    assert playback.segments == [url]
    assert_receive %Broadcast{event: "phase", payload: %{phase: "live"}}
    assert :sys.get_state(pid).phase == "live"
  end

  # EP-07
  test "deadline_ms and started_at_ms are absolute epoch milliseconds" do
    pid = start_episode()
    open_vote(pid)

    assert_receive %Broadcast{event: "vote_open", payload: %{deadline_ms: deadline}}
    assert_in_delta deadline, System.system_time(:millisecond) + 10_000, 1_000

    send(pid, {:timeline, :scene_boundary})
    send(pid, {:pipeline, 0, {:segment_ready, 0, "https://cdn.fal.example/seg0.mp4"}})

    assert_receive %Broadcast{event: "playback", payload: %{started_at_ms: started_at}}
    assert_in_delta started_at, System.system_time(:millisecond), 1_000
  end

  # EP-08
  test "zero presence: pipeline is never invoked and the episode holds" do
    pid = start_episode(%{viewer_count_fn: fn -> 0 end})

    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)
    assert Whn.PipelineStub.calls() == []

    open_vote(pid)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)

    assert Whn.PipelineStub.calls() == []
    assert :sys.get_state(pid).phase == "hold"
    assert_receive %Broadcast{event: "phase", payload: %{phase: "hold"}}
  end

  # EP-09
  test "viewers present: start_opening dispatched exactly once with nil winning_choice and last_frame_url" do
    pid = start_episode(%{viewer_count_fn: fn -> 3 end})

    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)

    assert [{:start_opening, ctx}] = Whn.PipelineStub.calls()
    assert ctx.winning_choice == nil
    assert ctx.last_frame_url == nil
    assert ctx.beat == 0
    assert ctx.episode == %{title: "Salary Just Entered", premise: "Lagos wahala"}
    assert :sys.get_state(pid).phase == "opening"

    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)
    assert [{:start_opening, _ctx}] = Whn.PipelineStub.calls()
  end

  test "join_sync returns the full EpisodeSync map with a personalized vote" do
    pid = start_episode()
    open_vote(pid)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 2)

    sync = Whn.EpisodeServer.join_sync(pid, "a1")
    assert Map.keys(sync) |> Enum.sort() == [:episode, :now_ms, :phase, :playback, :vote]
    assert sync.episode == %{title: "Salary Just Entered", premise: "Lagos wahala"}
    assert_in_delta sync.now_ms, System.system_time(:millisecond), 1_000
    assert sync.vote.your_vote == 2

    stranger = Whn.EpisodeServer.join_sync(pid, "somebody-else")
    assert stranger.vote.your_vote == nil
  end
end

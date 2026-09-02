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
    # REV-01: the close waits for the scheduled reveal window, it is not
    # broadcast in the same handler as the lock
    refute_receive %Broadcast{event: "vote_closed"}

    # the broadcasts go out before the pipeline dispatch inside the same
    # handle_info; sync on the server so the stub has recorded the call
    _ = :sys.get_state(pid)
    assert [{:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.winning_choice == "Hide the alert"
    assert ctx.beat == 1
    # EL-01: a canonized lock bumps the server-owned level by exactly one
    assert ctx.absurdity_level == 1
    assert :sys.get_state(pid).absurdity_level == 1

    send(pid, {:timeline, :vote_close})
    assert_receive %Broadcast{event: "vote_closed", payload: %{}}
  end

  # REV-02
  test "a stale vote_close falls through: duplicate close is silent, an open poll survives" do
    pid = start_episode()
    open_vote(pid)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 1)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a2", 1)
    send(pid, {:timeline, :vote_lock})
    assert_receive %Broadcast{event: "vote_locked"}

    send(pid, {:timeline, :vote_close})
    assert_receive %Broadcast{event: "vote_closed"}

    send(pid, {:timeline, :vote_close})
    refute_receive %Broadcast{event: "vote_closed"}

    # reopen for the next beat: a straggling vote_close must not touch it
    send(pid, {:pipeline, 1, {:celeris, @celeris}})
    send(pid, {:timeline, :vote_open})
    assert_receive %Broadcast{event: "vote_open"}

    send(pid, {:timeline, :vote_close})
    refute_receive %Broadcast{event: "vote_closed"}
    assert :sys.get_state(pid).vote.locked == false
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
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 0)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a2", 1)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)
    assert {:error, :locked} = Whn.EpisodeServer.vote(pid, "a1", 0)
  end

  test "below quorum: poll closes without a winner and no generation starts" do
    pid = start_episode()
    open_vote(pid)
    assert_receive %Broadcast{event: "vote_open"}

    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 2)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)

    assert_receive %Broadcast{event: "vote_closed"}
    refute_receive %Broadcast{event: "vote_locked"}
    assert Whn.PipelineStub.calls() == []

    state = :sys.get_state(pid)
    assert state.vote == nil
    assert state.beat == 0
    # EL-02: a below-quorum close never bumps the level
    assert state.absurdity_level == 0
    assert state.next_choices == ["Confront the boss", "Hide the alert", "Call Mama"]
  end

  test "revote re-opens the same options with a fresh deadline; quorum then generates" do
    pid = start_episode()
    open_vote(pid)
    assert_receive %Broadcast{event: "vote_open"}
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 1)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)
    assert_receive %Broadcast{event: "vote_closed"}

    send(pid, {:timeline, :revote})
    _ = :sys.get_state(pid)
    assert_receive %Broadcast{event: "vote_open", payload: reopened}
    assert reopened.options == ["Confront the boss", "Hide the alert", "Call Mama"]
    assert reopened.tallies == [0, 0, 0]
    assert_in_delta reopened.deadline_ms, System.system_time(:millisecond) + 10_000, 1_000

    {:ok, _} = Whn.EpisodeServer.vote(pid, "b1", 0)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "b2", 0)
    send(pid, {:timeline, :vote_lock})
    assert_receive %Broadcast{event: "vote_locked", payload: %{winner_idx: 0}}
    _ = :sys.get_state(pid)
    assert [{:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.winning_choice == "Confront the boss"
    # EL-02: one lock happened across the revote round-trip, not two
    assert ctx.absurdity_level == 1
  end

  test "revote with zero viewers reschedules instead of opening" do
    pid = start_episode(%{viewer_count_fn: fn -> 0 end})
    open_vote(pid)
    assert_receive %Broadcast{event: "vote_open"}
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)
    assert_receive %Broadcast{event: "vote_closed"}

    send(pid, {:timeline, :revote})
    _ = :sys.get_state(pid)
    refute_receive %Broadcast{event: "vote_open"}
  end

  # EL-03
  test "script engine cannot clobber the level: story_state_updates key is ignored" do
    pid = start_episode()

    celeris = Map.put(@celeris, :story_state_updates, %{"absurdity_level" => 99})
    send(pid, {:pipeline, 0, {:celeris, celeris}})
    send(pid, {:timeline, :vote_open})
    _ = :sys.get_state(pid)

    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 1)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a2", 1)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)

    # the model's value lands in story_state (merged, unread) but never
    # becomes the level: the ctx field is server-owned
    assert [{:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.absurdity_level == 1
    assert :sys.get_state(pid).absurdity_level == 1
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

  # EP-08 (quorum guard subsumes the old zero-presence hold at lock)
  test "zero presence: pipeline is never invoked" do
    pid = start_episode(%{viewer_count_fn: fn -> 0 end})

    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)
    assert Whn.PipelineStub.calls() == []

    open_vote(pid)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)

    assert Whn.PipelineStub.calls() == []
    refute_receive %Broadcast{event: "vote_locked"}
    assert :sys.get_state(pid).vote == nil
  end

  test "quorum met but zero viewers at lock: cycle is deferred until presence returns" do
    {:ok, viewers} = Agent.start_link(fn -> 1 end)
    pid = start_episode(%{viewer_count_fn: fn -> Agent.get(viewers, & &1) end})

    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)
    assert [{:start_opening, _}] = Whn.PipelineStub.calls()

    open_vote(pid)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 1)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a2", 1)

    Agent.update(viewers, fn _ -> 0 end)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)
    assert [{:start_opening, _}] = Whn.PipelineStub.calls()
    assert :sys.get_state(pid).phase == "hold"

    Agent.update(viewers, fn _ -> 2 end)
    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)
    assert [{:start_opening, _}, {:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.winning_choice == "Hide the alert"
  end

  # FC-02
  test "stored scene-end frame rides into the next cycle's ctx" do
    pid = start_episode()
    send(pid, {:pipeline, 0, {:last_frame, "mock://scene-end.jpg"}})
    open_vote(pid)

    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 1)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a2", 1)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)

    assert [{:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.last_frame_url == "mock://scene-end.jpg"
  end

  # FC-03
  test "frame intake is exempt from the stale-beat guard: any beat tag is stored" do
    pid = start_episode()
    assert :sys.get_state(pid).beat == 0

    send(pid, {:pipeline, 41, {:last_frame, "mock://stale-tag.jpg"}})
    assert :sys.get_state(pid).last_frame_url == "mock://stale-tag.jpg"
  end

  # FC-05
  test "frame arriving during a zero-viewer hold refreshes the parked cycle at dispatch" do
    {:ok, viewers} = Agent.start_link(fn -> 1 end)
    pid = start_episode(%{viewer_count_fn: fn -> Agent.get(viewers, & &1) end})

    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)
    assert [{:start_opening, _}] = Whn.PipelineStub.calls()

    open_vote(pid)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a1", 1)
    {:ok, _} = Whn.EpisodeServer.vote(pid, "a2", 1)

    Agent.update(viewers, fn _ -> 0 end)
    send(pid, {:timeline, :vote_lock})
    _ = :sys.get_state(pid)
    assert :sys.get_state(pid).phase == "hold"

    send(pid, {:pipeline, 1, {:last_frame, "mock://held.jpg"}})

    Agent.update(viewers, fn _ -> 2 end)
    send(pid, {:timeline, :presence_check})
    _ = :sys.get_state(pid)

    assert [{:start_opening, _}, {:start_cycle, ctx}] = Whn.PipelineStub.calls()
    assert ctx.last_frame_url == "mock://held.jpg"
    assert ctx.winning_choice == "Hide the alert"
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

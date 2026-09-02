defmodule Whn.IntegrationTest do
  # async: false — swaps the global :fal_impl and :celeris config, puts
  # Req.Test into shared mode (the pipeline task runs outside the test's
  # caller chain), and registers the app-wide :current episode.
  use WhnWeb.ChannelCase, async: false

  import Ecto.Query

  alias Phoenix.Socket.Broadcast
  alias Whn.Repo
  alias Whn.Schemas.{Beat, Decision, Episode, Vote}

  @title "Lagos Wahala — Salary Just Entered"

  @celeris_reply %{
    "scene_summary" => "The salary alert lands and the knocking starts.",
    "winning_choice" => "",
    "bridge" => %{
      "duration" => 10,
      "script" => "Tunde pockets the phone and reaches for the door.",
      "video_prompt" => "A young man pockets a buzzing phone and crosses a small Lagos room."
    },
    "next_scene" => %{
      "duration" => 30,
      "script" => "The landlord fills the doorway before the phone stops buzzing.",
      "video_prompt" => "A landlord blocks a doorway while the man weighs his words."
    },
    "next_choices" => ["Open the door", "Silence the phone", "Climb out the window"],
    "story_state_updates" => %{"time_of_day" => "morning rush"}
  }

  setup do
    fixture =
      Path.join(
        System.tmp_dir!(),
        "whn_integration_test_#{System.unique_integer([:positive])}.mp4"
      )

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=144x256:rate=10", fixture],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm(fixture) end)

    # Unlinked: a linked mock dies with the test process, before on_exit —
    # but the cycle task's trailing frame extraction can still be running
    # then. drain_tasks (registered per test, so it runs first) waits the
    # task out against a live mock; this stop follows.
    {:ok, mock} = Whn.FalMock.start(video: fixture)
    on_exit(fn -> if Process.alive?(mock), do: Agent.stop(mock) end)

    previous_fal = Application.get_env(:whn, :fal_impl)
    Application.put_env(:whn, :fal_impl, Whn.FalMock)

    System.put_env("CELERIS_TEST_KEY", "test-key")
    previous_celeris = Application.get_env(:whn, :celeris)

    Application.put_env(:whn, :celeris,
      key_env: "CELERIS_TEST_KEY",
      req_options: [plug: {Req.Test, Whn.Celeris}]
    )

    on_exit(fn ->
      restore = fn key, previous ->
        if previous do
          Application.put_env(:whn, key, previous)
        else
          Application.delete_env(:whn, key)
        end
      end

      restore.(:fal_impl, previous_fal)
      restore.(:celeris, previous_celeris)
    end)

    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    Req.Test.stub(Whn.Celeris, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(@celeris_reply)}}]
      })
    end)

    Phoenix.PubSub.subscribe(Whn.PubSub, "episode:live")

    %{fixture: fixture}
  end

  # E2E-01
  test "the seed episode boots: row, registered server, phase broadcast" do
    pid = start_episode!()

    assert [%Episode{} = row] = Repo.all(from e in Episode, where: e.title == @title)
    assert row.seed == 20_260_831
    assert row.story_state["protagonist"]["name"] == "Tunde"
    assert Whn.Episodes.current() == pid

    send(pid, {:timeline, :presence_check})
    assert_receive %Broadcast{event: "phase", payload: %{phase: "opening"}}, 5_000

    finish_opening()
  end

  # E2E-02
  test "a driven cycle persists the decision, both votes, and the beats", %{fixture: fixture} do
    pid = start_episode!()

    send(pid, {:timeline, :presence_check})
    assert_receive %Broadcast{event: "phase", payload: %{phase: "opening"}}, 5_000
    finish_opening()

    {_reply, socket_a} = join!("anon-int-a")
    {_reply, socket_b} = join!("anon-int-b")

    send(pid, {:timeline, :vote_open})
    assert_receive %Broadcast{event: "vote_open", payload: %{options: options}}, 5_000
    assert options == @celeris_reply["next_choices"]

    ref_a = push(socket_a, "vote", %{"option_idx" => 1})
    assert_reply ref_a, :ok, %{tallies: [0, 1, 0], your_vote: 1}
    ref_b = push(socket_b, "vote", %{"option_idx" => 1})
    assert_reply ref_b, :ok, %{tallies: [0, 2, 0], your_vote: 1}

    send(pid, {:timeline, :vote_lock})

    assert_receive %Broadcast{
                     event: "vote_locked",
                     payload: %{winner_idx: 1, tallies: [0, 2, 0]}
                   },
                   5_000

    # the lock handler finalizes the decision before serving the next call
    _ = :sys.get_state(pid)

    # the winner-only cycle: bridge, then three chained segments
    for _ <- 1..3, do: assert_receive(%Broadcast{event: "preload"}, 15_000)

    episode = Repo.one!(from e in Episode, where: e.title == @title)

    decision = Repo.one!(from d in Decision, where: d.episode_id == ^episode.id)
    assert decision.beat_idx == 0
    assert decision.question == "What happens next?"
    assert decision.options == options
    assert decision.winner_idx == 1
    assert decision.tallies == [0, 2, 0]

    await(fn ->
      anon_ids = Repo.all(from v in Vote, where: v.decision_id == ^decision.id, select: v.anon_id)
      Enum.sort(anon_ids) == ["anon-int-a", "anon-int-b"]
    end)

    assert Repo.all(from v in Vote, select: v.option_idx) == [1, 1]

    scene_query = from b in Beat, where: b.episode_id == ^episode.id and b.kind == "scene"

    await(fn ->
      match?(%Beat{segments: [_, _, _]}, Repo.one(from b in scene_query, where: b.idx == 1))
    end)

    scene = Repo.one!(from b in scene_query, where: b.idx == 1)
    assert scene.segments == [fixture, fixture, fixture]
    assert scene.meta["seed"] == 20_260_831 + 1

    await(fn ->
      Repo.exists?(from b in Beat, where: b.episode_id == ^episode.id and b.kind == "bridge")
    end)

    bridge =
      Repo.one!(from b in Beat, where: b.episode_id == ^episode.id and b.kind == "bridge")

    assert bridge.idx == 1
    assert bridge.segments == [fixture]
  end

  defp start_episode! do
    attrs = Map.put(Whn.Seed.salary_just_entered(), :viewer_count_fn, fn -> 1 end)
    pid = Whn.Episodes.start!(attrs)

    on_exit(fn ->
      ref = Process.monitor(pid)
      _ = DynamicSupervisor.terminate_child(Whn.EpisodeSupervisor, pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5_000 -> :ok
      end

      drain_tasks()
      await(fn -> Whn.Episodes.current() == nil end)
    end)

    pid
  end

  defp join!(anon_id) do
    {:ok, socket} = connect(WhnWeb.UserSocket, %{"anon_id" => anon_id})
    {:ok, reply, socket} = subscribe_and_join(socket, "episode:live", %{})
    {reply, socket}
  end

  # The opening broadcasts one preload per segment; consuming all three means
  # the pipeline task has finished and next_choices are in the server state.
  defp finish_opening do
    for _ <- 1..3, do: assert_receive(%Broadcast{event: "preload"}, 15_000)
    assert_receive %Broadcast{event: "playback", payload: %{kind: "scene", beat: 0}}, 5_000
  end

  # Repeated cheap checks instead of Process.sleep: fire-and-forget writes
  # land within a handful of iterations once their broadcast has arrived.
  defp await(fun, attempts \\ 5_000) do
    cond do
      fun.() -> :ok
      attempts <= 0 -> flunk("timed out waiting for an asynchronous write")
      true -> await(fun, attempts - 1)
    end
  end

  defp drain_tasks do
    for task <- Task.Supervisor.children(Whn.TaskSupervisor) do
      ref = Process.monitor(task)

      receive do
        {:DOWN, ^ref, :process, _pid, _reason} -> :ok
      after
        15_000 -> :ok
      end
    end
  end
end

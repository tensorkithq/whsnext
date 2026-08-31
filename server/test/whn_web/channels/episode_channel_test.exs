defmodule WhnWeb.EpisodeChannelTest do
  use WhnWeb.ChannelCase, async: false

  @celeris %{
    scene_summary: "Ade sees the salary alert",
    winning_choice: nil,
    bridge: nil,
    next_scene: %{duration: 30, script: "beat script", video_prompt: "beat prompt"},
    next_choices: ["Confront the boss", "Hide the alert", "Call Mama"],
    story_state_updates: %{}
  }

  setup do
    Application.put_env(:whn, :pipeline_impl, Whn.PipelineStub)
    on_exit(fn -> Application.delete_env(:whn, :pipeline_impl) end)
    start_supervised!(Whn.PipelineStub)

    episode =
      start_supervised!(
        {Whn.EpisodeServer,
         %{
           id: "ep-chan",
           title: "Salary Just Entered",
           premise: "Lagos wahala",
           seed: 7,
           viewer_count_fn: fn -> 1 end
         }}
      )

    %{episode: episode}
  end

  defp join!(anon_id) do
    {:ok, socket} = connect(WhnWeb.UserSocket, %{"anon_id" => anon_id})
    {:ok, reply, socket} = subscribe_and_join(socket, "episode:live", %{})
    {reply, socket}
  end

  defp open_vote(episode) do
    send(episode, {:pipeline, 0, {:celeris, @celeris}})
    send(episode, {:timeline, :vote_open})
    _ = :sys.get_state(episode)
  end

  # EP-01
  test "join replies with the full EpisodeSync" do
    {reply, _socket} = join!("anon-1")

    assert reply |> Map.keys() |> Enum.sort() == [:episode, :now_ms, :phase, :playback, :vote]
    assert reply.episode == %{title: "Salary Just Entered", premise: "Lagos wahala"}
    assert reply.phase == "idle"
  end

  # EP-02
  test "after join, presence_state is pushed keyed by anon_id" do
    {_reply, _socket} = join!("anon-42")

    assert_push "presence_state", presence
    assert %{metas: [_ | _]} = presence["anon-42"]
  end

  # EP-03
  test "one vote per anon_id: a second push replies with the original pick", %{episode: episode} do
    open_vote(episode)
    {_reply, socket} = join!("anon-7")

    ref = push(socket, "vote", %{"option_idx" => 1})
    assert_reply ref, :ok, %{tallies: [0, 1, 0], your_vote: 1}

    ref = push(socket, "vote", %{"option_idx" => 2})
    assert_reply ref, :ok, %{tallies: [0, 1, 0], your_vote: 1}
  end

  # EP-04
  test "votes after lock reply with reason locked", %{episode: episode} do
    open_vote(episode)
    {_reply, socket} = join!("anon-9")

    send(episode, {:timeline, :vote_lock})
    _ = :sys.get_state(episode)

    ref = push(socket, "vote", %{"option_idx" => 0})
    assert_reply ref, :error, %{reason: "locked"}
  end

  # D-04
  test "any other episode subtopic rejects the join" do
    {:ok, socket} = connect(WhnWeb.UserSocket, %{"anon_id" => "anon-x"})
    assert {:error, %{reason: "not_found"}} = subscribe_and_join(socket, "episode:other", %{})
  end

  test "socket connect requires a non-empty anon_id" do
    assert :error = connect(WhnWeb.UserSocket, %{})
    assert :error = connect(WhnWeb.UserSocket, %{"anon_id" => ""})
  end
end

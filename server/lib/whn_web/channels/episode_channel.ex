defmodule WhnWeb.EpisodeChannel do
  @moduledoc """
  Thin translator between the wire protocol and the episode server. The
  `live` subtopic resolves to the single currently-running episode; the
  join reply is the full sync snapshot, so reconnects need no extra
  round-trip.
  """

  use WhnWeb, :channel

  alias WhnWeb.Presence

  @impl true
  def join("episode:live", _params, socket) do
    case Whn.Episodes.current() do
      nil ->
        {:error, %{reason: "no_episode"}}

      episode ->
        send(self(), :after_join)
        sync = Whn.EpisodeServer.join_sync(episode, socket.assigns.anon_id)
        {:ok, sync, assign(socket, :episode_pid, episode)}
    end
  end

  def join("episode:" <> _other, _params, _socket) do
    {:error, %{reason: "not_found"}}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _ref} =
      Presence.track(socket, socket.assigns.anon_id, %{
        online_at: System.system_time(:second)
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("vote", %{"option_idx" => option_idx}, socket) when is_integer(option_idx) do
    case Whn.EpisodeServer.vote(socket.assigns.episode_pid, socket.assigns.anon_id, option_idx) do
      {:ok, reply} -> {:reply, {:ok, reply}, socket}
      {:error, :locked} -> {:reply, {:error, %{reason: "locked"}}, socket}
      {:error, :no_open_vote} -> {:reply, {:error, %{reason: "no_open_vote"}}, socket}
    end
  end
end

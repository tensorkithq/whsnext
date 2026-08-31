defmodule WhnWeb.UserSocket do
  use Phoenix.Socket

  channel "episode:*", WhnWeb.EpisodeChannel

  @impl true
  def connect(%{"anon_id" => anon_id}, socket, _connect_info)
      when is_binary(anon_id) and anon_id != "" do
    {:ok, assign(socket, :anon_id, anon_id)}
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "anon:#{socket.assigns.anon_id}"
end

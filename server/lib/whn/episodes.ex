defmodule Whn.Episodes do
  @moduledoc """
  Lifecycle and lookup for live episode processes. One episode runs at a
  time; the channel resolves the `episode:live` topic through `current/0`.
  """

  @doc """
  Creates the episode row, then starts an episode server carrying its id —
  the database row is the durable identity. Raises on failure.
  """
  def start!(attrs) do
    {:ok, episode} = Whn.Store.create_episode(attrs)
    attrs = attrs |> Map.put(:id, episode.id) |> Map.put(:episode_id, episode.id)

    case DynamicSupervisor.start_child(Whn.EpisodeSupervisor, {Whn.EpisodeServer, attrs}) do
      {:ok, pid} -> pid
      {:error, reason} -> raise "could not start episode: #{inspect(reason)}"
    end
  end

  @doc "The pid of the single currently-running episode, or nil."
  def current do
    case Registry.lookup(Whn.EpisodeRegistry, :current) do
      [{pid, _id}] -> pid
      [] -> nil
    end
  end
end

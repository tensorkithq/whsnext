defmodule Whn.Episodes do
  @moduledoc """
  Lifecycle and lookup for live episode processes. One episode runs at a
  time; the channel resolves the `episode:live` topic through `current/0`.
  """

  @doc "Starts an episode server under the episode supervisor. Raises on failure."
  def start!(attrs) do
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

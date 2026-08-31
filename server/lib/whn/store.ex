defmodule Whn.Store do
  @moduledoc """
  Synchronous persistence for the live episode loop.

  Every function writes (or reads) inline in the caller's process —
  hot-path callers are responsible for wrapping these in fire-and-forget
  tasks if they cannot afford the round trip.
  """

  alias Whn.Repo
  alias Whn.Schemas.{Beat, Decision, Episode, Vote}

  def create_episode(attrs) do
    %Episode{}
    |> Episode.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Insert-or-replace keyed on `(episode_id, idx, kind)`, so re-generating
  a beat (retry, later segment arriving) updates the row in place.
  """
  def upsert_beat(episode_id, attrs) do
    %Beat{episode_id: episode_id}
    |> Beat.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:segments, :meta, :script, :video_prompt]},
      conflict_target: [:episode_id, :idx, :kind]
    )
  end

  def record_decision(episode_id, attrs) do
    %Decision{episode_id: episode_id}
    |> Decision.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  First write wins: the unique index on `(decision_id, anon_id)` plus
  `on_conflict: :nothing` makes a repeat vote a no-op at the database
  level, whatever the in-memory tally layer does.
  """
  def record_vote(decision_id, anon_id, option_idx) do
    %Vote{decision_id: decision_id, anon_id: anon_id, option_idx: option_idx}
    |> Repo.insert(on_conflict: :nothing)
  end

  def update_story_state(episode_id, story_state) do
    Episode
    |> Repo.get!(episode_id)
    |> Ecto.Changeset.change(story_state: story_state)
    |> Repo.update()
  end
end

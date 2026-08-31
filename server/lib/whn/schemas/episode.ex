defmodule Whn.Schemas.Episode do
  use Ecto.Schema

  import Ecto.Changeset

  schema "episodes" do
    field :title, :string
    field :premise, :string
    field :seed, :integer
    field :phase, :string
    field :story_state, :map

    timestamps()
  end

  def changeset(episode, attrs) do
    cast(episode, attrs, [:title, :premise, :seed, :phase, :story_state])
  end
end

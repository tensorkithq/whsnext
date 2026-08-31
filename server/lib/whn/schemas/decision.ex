defmodule Whn.Schemas.Decision do
  use Ecto.Schema

  import Ecto.Changeset

  schema "decisions" do
    field :beat_idx, :integer
    field :question, :string
    field :options, {:array, :string}
    field :tallies, {:array, :integer}
    field :winner_idx, :integer
    field :deadline_ms, :integer

    belongs_to :episode, Whn.Schemas.Episode

    timestamps()
  end

  def changeset(decision, attrs) do
    cast(decision, attrs, [:beat_idx, :question, :options, :tallies, :winner_idx, :deadline_ms])
  end
end

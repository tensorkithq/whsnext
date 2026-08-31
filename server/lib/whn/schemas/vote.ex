defmodule Whn.Schemas.Vote do
  use Ecto.Schema

  schema "votes" do
    field :anon_id, :string
    field :option_idx, :integer

    belongs_to :decision, Whn.Schemas.Decision

    timestamps()
  end
end

defmodule Whn.Schemas.Beat do
  use Ecto.Schema

  import Ecto.Changeset

  schema "beats" do
    field :idx, :integer
    field :kind, :string
    field :script, :string
    field :video_prompt, :string
    field :segments, {:array, :string}
    field :meta, :map

    belongs_to :episode, Whn.Schemas.Episode

    timestamps()
  end

  def changeset(beat, attrs) do
    cast(beat, attrs, [:idx, :kind, :script, :video_prompt, :segments, :meta])
  end
end

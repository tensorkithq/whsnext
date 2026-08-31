defmodule Whn.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    create table(:episodes) do
      add :title, :string
      add :premise, :text
      add :seed, :integer
      add :phase, :string
      add :story_state, :map

      timestamps()
    end

    create table(:beats) do
      add :episode_id, references(:episodes)
      add :idx, :integer
      add :kind, :string
      add :script, :text
      add :video_prompt, :text
      add :segments, {:array, :string}
      add :meta, :map

      timestamps()
    end

    create unique_index(:beats, [:episode_id, :idx, :kind])

    create table(:decisions) do
      add :episode_id, references(:episodes)
      add :beat_idx, :integer
      add :question, :string
      add :options, {:array, :string}
      add :tallies, {:array, :integer}
      add :winner_idx, :integer
      add :deadline_ms, :bigint

      timestamps()
    end

    create table(:votes) do
      add :decision_id, references(:decisions)
      add :anon_id, :string
      add :option_idx, :integer

      timestamps()
    end

    create unique_index(:votes, [:decision_id, :anon_id])
  end
end

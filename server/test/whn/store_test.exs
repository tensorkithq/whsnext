defmodule Whn.StoreTest do
  use Whn.DataCase, async: true

  alias Whn.Schemas.{Beat, Decision, Episode, Vote}
  alias Whn.Store

  defp create_episode! do
    {:ok, episode} =
      Store.create_episode(%{
        title: "Salary Just Entered",
        premise: "Adaobi's salary lands and everyone in Lagos wants a piece of it.",
        seed: 42,
        phase: "live",
        story_state: %{"money" => 250_000}
      })

    episode
  end

  defp record_decision!(episode, attrs) do
    {:ok, decision} =
      Store.record_decision(
        episode.id,
        Map.merge(
          %{
            beat_idx: 0,
            question: "What does Adaobi do?",
            options: ["Pay the rent", "Buy the shoes"],
            tallies: [0, 0],
            deadline_ms: 1_756_000_000_000
          },
          attrs
        )
      )

    decision
  end

  test "a second vote from the same anon_id leaves the original untouched" do
    episode = create_episode!()
    decision = record_decision!(episode, %{})

    assert {:ok, _} = Store.record_vote(decision.id, "anon-1", 0)
    assert {:ok, _} = Store.record_vote(decision.id, "anon-1", 1)

    assert [%Vote{anon_id: "anon-1", option_idx: 0}] =
             Repo.all(from v in Vote, where: v.decision_id == ^decision.id)
  end

  test "episode, beat, decision, and story state round-trip through the database" do
    episode = create_episode!()

    segments = ["https://fal.media/seg-0.mp4", "https://fal.media/seg-1.mp4"]

    {:ok, _beat} =
      Store.upsert_beat(episode.id, %{
        idx: 0,
        kind: "scene",
        script: "ADAOBI: This money must last the month.",
        video_prompt: "Vertical shot, Lagos apartment, phone buzzing with alerts.",
        segments: segments,
        meta: %{"seed" => 42}
      })

    decision = record_decision!(episode, %{tallies: [7, 3], winner_idx: 0})

    {:ok, _} = Store.update_story_state(episode.id, %{"money" => 180_000})

    beat = Repo.get_by!(Beat, episode_id: episode.id, idx: 0, kind: "scene")
    assert beat.script == "ADAOBI: This money must last the month."
    assert beat.video_prompt == "Vertical shot, Lagos apartment, phone buzzing with alerts."
    assert beat.segments == segments
    assert beat.meta == %{"seed" => 42}

    persisted = Repo.get!(Decision, decision.id)
    assert persisted.beat_idx == 0
    assert persisted.question == "What does Adaobi do?"
    assert persisted.options == ["Pay the rent", "Buy the shoes"]
    assert persisted.tallies == [7, 3]
    assert persisted.winner_idx == 0
    assert persisted.deadline_ms == 1_756_000_000_000

    assert Repo.get!(Episode, episode.id).story_state == %{"money" => 180_000}
  end

  test "upsert_beat replaces the generated fields on an existing (episode, idx, kind)" do
    episode = create_episode!()
    attrs = %{idx: 1, kind: "bridge", script: "v1", video_prompt: "p1", segments: [], meta: %{}}

    {:ok, _} = Store.upsert_beat(episode.id, attrs)

    {:ok, _} =
      Store.upsert_beat(episode.id, %{
        attrs
        | script: "v2",
          segments: ["https://fal.media/bridge.mp4"]
      })

    assert [beat] = Repo.all(from b in Beat, where: b.episode_id == ^episode.id)
    assert beat.script == "v2"
    assert beat.segments == ["https://fal.media/bridge.mp4"]
  end
end

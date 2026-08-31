defmodule Whn.Seed do
  @moduledoc """
  Canned episode content. Each function returns the attrs map that
  `Whn.Episodes.start!/1` and the database seed script consume.
  """

  @doc """
  Lagos Wahala — "Salary Just Entered", the launch episode.

  The fixed seed keeps generation reproducible across runs; the initial
  story state gives the script engine the protagonist, the money, and the
  standing pressures every choice will push against.
  """
  def salary_just_entered do
    %{
      title: "Lagos Wahala — Salary Just Entered",
      premise:
        "Tunde's salary has just landed, and all of Lagos seems to know. " <>
          "The landlord is at the door about rent, his mother keeps calling for attention, " <>
          "and his friend Emeka has arrived with a can't-fail business proposal — all while " <>
          "the morning commute looms and his girlfriend is still waiting on a promise.",
      seed: 20_260_831,
      story_state: %{
        "protagonist" => %{"name" => "Tunde", "archetype" => "overstretched optimist"},
        "money_ngn" => 250_000,
        "relationships" => %{
          "landlord" => "owed two months of rent and out of patience",
          "mother" => "calls every morning and suspects he is hiding good news",
          "friend" => "Emeka needs capital today for a POS business that cannot fail",
          "partner" => "Amara is still waiting on the anniversary dinner he promised"
        },
        "active_problems" => [
          "rent is overdue and the landlord knows it is salary day",
          "the danfo commute to work starts within the hour",
          "everyone who matters wants a piece of the salary"
        ],
        "location" => "one-room apartment, Surulere, Lagos",
        "time_of_day" => "early morning",
        "current_objective" => "make the salary survive the day"
      }
    }
  end
end

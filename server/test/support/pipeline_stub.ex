defmodule Whn.PipelineStub do
  @moduledoc """
  Test double for the generation pipeline. Records every invocation in an
  Agent so tests can assert on dispatch behavior; produces no pipeline
  messages of its own.
  """

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> [] end, name: __MODULE__)
  end

  @doc "Every recorded invocation, oldest first."
  def calls do
    __MODULE__ |> Agent.get(& &1) |> Enum.reverse()
  end

  def start_opening(_dest, ctx) do
    Agent.update(__MODULE__, &[{:start_opening, ctx} | &1])
    {:ok, self()}
  end

  def start_cycle(_dest, ctx) do
    Agent.update(__MODULE__, &[{:start_cycle, ctx} | &1])
    {:ok, self()}
  end
end

defmodule Whn.FalMock do
  @moduledoc """
  Scripted `Whn.Fal` implementation for pipeline tests — zero fal spend.

  Records every call as `{fun, args}` in an Agent so tests can assert on the
  parameter contract. Video-producing calls return the local mp4 fixture the
  mock was started with, so `Whn.Frames.last_frame/1` runs for real against
  it. `fail_once/1` arms a one-shot `{:error, :fal_flaked}` for a function,
  exercising the retry path. `fail_on_call/2` arms one for the Nth call to
  a function instead, targeting a specific attempt past any retries.
  """

  @behaviour Whn.Fal

  use Agent

  def start_link(opts) do
    Agent.start_link(fn -> initial_state(opts) end, name: __MODULE__)
  end

  @doc """
  Starts the mock unlinked, for tests whose pipeline task outlives the test
  process: linked and supervised processes both die before `on_exit`
  callbacks run, so the caller drains the task and stops the mock there.
  """
  def start(opts) do
    Agent.start(fn -> initial_state(opts) end, name: __MODULE__)
  end

  defp initial_state(opts) do
    %{
      video: Keyword.fetch!(opts, :video),
      calls: [],
      fail_once: MapSet.new(),
      fail_on: %{},
      counts: %{}
    }
  end

  @doc "Every recorded `{fun, args}` invocation, oldest first."
  def calls do
    __MODULE__ |> Agent.get(& &1.calls) |> Enum.reverse()
  end

  @doc "Arms a single `{:error, :fal_flaked}` for the next call to `fun`."
  def fail_once(fun) do
    Agent.update(__MODULE__, &%{&1 | fail_once: MapSet.put(&1.fail_once, fun)})
  end

  @doc "Arms a single `{:error, :fal_flaked}` for the Nth call to `fun` (1-based, counted per fun)."
  def fail_on_call(fun, n) do
    Agent.update(__MODULE__, &%{&1 | fail_on: Map.put(&1.fail_on, fun, n)})
  end

  @impl true
  def t2v(prompt, opts) do
    dispatch(:t2v, [prompt, opts], fn state -> {:ok, %{url: state.video}} end)
  end

  @impl true
  def i2v(prompt, image_url, opts) do
    dispatch(:i2v, [prompt, image_url, opts], fn state -> {:ok, %{url: state.video}} end)
  end

  @impl true
  def flux(prompt, opts) do
    dispatch(:flux, [prompt, opts], fn _state -> {:ok, %{url: "mock://flux-frame.png"}} end)
  end

  @impl true
  def vision(prompt, opts) do
    dispatch(:vision, [prompt, opts], fn _state -> {:ok, %{output: "{}"}} end)
  end

  @impl true
  def upload(path) do
    dispatch(:upload, [path], fn _state ->
      {:ok, "mock://frame-#{System.unique_integer([:positive])}.jpg"}
    end)
  end

  defp dispatch(fun, args, respond) do
    Agent.get_and_update(__MODULE__, fn state ->
      count = Map.get(state.counts, fun, 0) + 1

      state = %{
        state
        | calls: [{fun, args} | state.calls],
          counts: Map.put(state.counts, fun, count)
      }

      cond do
        MapSet.member?(state.fail_once, fun) ->
          {{:error, :fal_flaked}, %{state | fail_once: MapSet.delete(state.fail_once, fun)}}

        Map.get(state.fail_on, fun) == count ->
          {{:error, :fal_flaked}, %{state | fail_on: Map.delete(state.fail_on, fun)}}

        true ->
          {respond.(state), state}
      end
    end)
  end
end

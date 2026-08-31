defmodule Whn.FalTest do
  # async: false — swaps the global :fal_impl for the recording stub below.
  use ExUnit.Case, async: false

  defmodule RecordingFal do
    @behaviour Whn.Fal

    # Whn.Fal dispatches in the calling process, so the test process
    # receives its own recording messages.
    defp record(fun, args), do: send(self(), {:fal_call, fun, args})

    @impl true
    def t2v(prompt, opts) do
      record(:t2v, [prompt, opts])
      {:ok, %{url: "stub://t2v.mp4"}}
    end

    @impl true
    def i2v(prompt, image_url, opts) do
      record(:i2v, [prompt, image_url, opts])
      {:ok, %{url: "stub://i2v.mp4"}}
    end

    @impl true
    def flux(prompt, opts) do
      record(:flux, [prompt, opts])
      {:ok, %{url: "stub://flux.jpg"}}
    end

    @impl true
    def vision(prompt, opts) do
      record(:vision, [prompt, opts])
      {:ok, %{output: "stub output"}}
    end

    @impl true
    def upload(path) do
      record(:upload, [path])
      {:ok, "stub://upload.jpg"}
    end
  end

  setup do
    previous = Application.get_env(:whn, :fal_impl)
    Application.put_env(:whn, :fal_impl, RecordingFal)

    on_exit(fn ->
      if previous do
        Application.put_env(:whn, :fal_impl, previous)
      else
        Application.delete_env(:whn, :fal_impl)
      end
    end)

    :ok
  end

  test "all five operations dispatch to the configured impl with args intact" do
    assert {:ok, %{url: "stub://t2v.mp4"}} = Whn.Fal.t2v("a street scene", duration: 10)
    assert_received {:fal_call, :t2v, ["a street scene", [duration: 10]]}

    assert {:ok, %{url: "stub://i2v.mp4"}} =
             Whn.Fal.i2v("continue the scene", "hosted://frame.jpg", seed: 7)

    assert_received {:fal_call, :i2v, ["continue the scene", "hosted://frame.jpg", [seed: 7]]}

    assert {:ok, %{url: "stub://flux.jpg"}} =
             Whn.Fal.flux("opening still", image_size: %{width: 720, height: 1280})

    assert_received {:fal_call, :flux, ["opening still", _opts]}

    assert {:ok, %{output: "stub output"}} = Whn.Fal.vision("describe the frame", [])
    assert_received {:fal_call, :vision, ["describe the frame", []]}

    assert {:ok, "stub://upload.jpg"} = Whn.Fal.upload("/tmp/frame.jpg")
    assert_received {:fal_call, :upload, ["/tmp/frame.jpg"]}
  end

  test "opts default to an empty list on every arity-optional operation" do
    assert {:ok, _} = Whn.Fal.t2v("prompt only")
    assert_received {:fal_call, :t2v, ["prompt only", []]}

    assert {:ok, _} = Whn.Fal.i2v("prompt only", "hosted://frame.jpg")
    assert_received {:fal_call, :i2v, ["prompt only", "hosted://frame.jpg", []]}

    assert {:ok, _} = Whn.Fal.flux("prompt only")
    assert_received {:fal_call, :flux, ["prompt only", []]}

    assert {:ok, _} = Whn.Fal.vision("prompt only")
    assert_received {:fal_call, :vision, ["prompt only", []]}
  end
end

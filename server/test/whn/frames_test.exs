defmodule Whn.FramesTest do
  # async: false — swaps the global :fal_impl for the stub below.
  use ExUnit.Case, async: false

  defmodule StubFal do
    @behaviour Whn.Fal

    import ExUnit.Assertions

    @impl true
    def t2v(_prompt, _opts), do: {:error, :stub}

    @impl true
    def i2v(_prompt, _image_url, _opts), do: {:error, :stub}

    @impl true
    def flux(_prompt, _opts), do: {:error, :stub}

    @impl true
    def vision(_prompt, _opts), do: {:error, :stub}

    @impl true
    def upload(path) do
      assert File.exists?(path)
      assert Path.extname(path) == ".jpg"
      {:ok, "stub://frame.jpg"}
    end
  end

  setup do
    previous = Application.get_env(:whn, :fal_impl)
    Application.put_env(:whn, :fal_impl, StubFal)

    on_exit(fn ->
      if previous do
        Application.put_env(:whn, :fal_impl, previous)
      else
        Application.delete_env(:whn, :fal_impl)
      end
    end)

    :ok
  end

  defp tmp_path(name) do
    Path.join(System.tmp_dir!(), "whn_frames_test_#{System.unique_integer([:positive])}_#{name}")
  end

  test "extracts the last frame of a local clip and uploads it" do
    fixture = tmp_path("fixture.mp4")

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        ["-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=144x256:rate=10", fixture],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm(fixture) end)

    assert {:ok, "stub://frame.jpg"} = Whn.Frames.last_frame(fixture)
  end

  # FC-06
  test "extracts a frame when the audio track outlasts the video stream" do
    fixture = tmp_path("overhang.mp4")

    # video 1s, audio 1.5s: -sseof measures from container duration, so the
    # 0.5s overhang puts the -0.25 seek at 1.25s — past the last video frame
    # — and only the -1 retry (seek at 0.5s) lands on one
    {_output, 0} =
      System.cmd(
        "ffmpeg",
        [
          "-y",
          "-f",
          "lavfi",
          "-i",
          "testsrc=duration=1:size=144x256:rate=10",
          "-f",
          "lavfi",
          "-i",
          "sine=frequency=440:duration=1.5",
          fixture
        ],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm(fixture) end)

    assert {:ok, "stub://frame.jpg"} = Whn.Frames.last_frame(fixture)
  end

  test "returns an error when the input is not a readable video" do
    bogus = tmp_path("bogus.mp4")
    File.write!(bogus, "not a video")
    on_exit(fn -> File.rm(bogus) end)

    assert {:error, _reason} = Whn.Frames.last_frame(bogus)
  end
end

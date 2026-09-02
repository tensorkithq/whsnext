defmodule Whn.PipelineTest do
  # async: false — swaps the global :fal_impl and :celeris app config.
  use ExUnit.Case, async: false

  @celeris_reply %{
    "scene_summary" => "The decision lands and the day keeps moving.",
    "winning_choice" => "Pay the landlord half",
    "bridge" => %{
      "duration" => 10,
      "script" => "He pockets the envelope and heads for the stairs.",
      "video_prompt" => "The protagonist pockets an envelope and climbs a stairwell."
    },
    "next_scene" => %{
      "duration" => 30,
      "script" => "The landlord counts, recounts, and starts an argument.",
      "video_prompt" => "A landlord counts cash in a doorway while the protagonist waits."
    },
    "next_choices" => ["Argue the total", "Walk away mid-count", "Offer to fix the gate instead"],
    "story_state_updates" => %{"money" => 90_000}
  }

  setup do
    fixture =
      Path.join(
        System.tmp_dir!(),
        "whn_pipeline_test_#{System.unique_integer([:positive])}.mp4"
      )

    {_output, 0} =
      System.cmd(
        "ffmpeg",
        ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=144x256:rate=10", fixture],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm(fixture) end)

    start_supervised!({Whn.FalMock, video: fixture})

    previous_fal = Application.get_env(:whn, :fal_impl)
    Application.put_env(:whn, :fal_impl, Whn.FalMock)

    System.put_env("CELERIS_TEST_KEY", "test-key")
    previous_celeris = Application.get_env(:whn, :celeris)

    Application.put_env(:whn, :celeris,
      key_env: "CELERIS_TEST_KEY",
      req_options: [plug: {Req.Test, Whn.Celeris}]
    )

    on_exit(fn ->
      restore = fn key, previous ->
        if previous do
          Application.put_env(:whn, key, previous)
        else
          Application.delete_env(:whn, key)
        end
      end

      restore.(:fal_impl, previous_fal)
      restore.(:celeris, previous_celeris)
    end)

    Req.Test.stub(Whn.Celeris, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => Jason.encode!(@celeris_reply)}}]
      })
    end)

    :ok
  end

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %{
        beat: 1,
        seed: 100,
        episode: %{
          title: "Salary Just Entered",
          premise: "Salary enters; everyone wants a piece."
        },
        story_state: %{},
        winning_choice: "Pay the landlord half",
        last_frame_url: nil,
        history: []
      },
      overrides
    )
  end

  # CEL-04
  test "cycle stage messages arrive in the pinned order" do
    {:ok, _pid} = Whn.Pipeline.start_cycle(self(), ctx(%{last_frame_url: "mock://prev.jpg"}))

    assert_receive {:pipeline, 1, first}, 10_000
    assert {:celeris, result} = first
    assert [_, _, _] = result.next_choices

    assert_receive {:pipeline, 1, second}, 10_000
    assert {:bridge_ready, bridge_url} = second
    assert is_binary(bridge_url)

    for idx <- 0..2 do
      assert_receive {:pipeline, 1, message}, 10_000
      assert {:segment_ready, ^idx, url} = message
      assert is_binary(url)
    end

    refute_receive {:pipeline, _beat, {:error, _stage, _reason}}, 100
  end

  # CEL-05
  test "cycle honors the i2v param contract with seed = episode seed + beat" do
    {:ok, _pid} = Whn.Pipeline.start_cycle(self(), ctx(%{last_frame_url: "mock://prev.jpg"}))
    assert_receive {:pipeline, 1, {:segment_ready, 2, _url}}, 10_000

    i2v_calls = for {:i2v, args} <- Whn.FalMock.calls(), do: args
    # bridge + 3 segments, all image-to-video off the previous frame
    assert length(i2v_calls) == 4

    for [_prompt, _image, opts] <- i2v_calls do
      assert opts[:duration] == 10
      assert opts[:resolution] == "480P"
      assert opts[:prompt_expansion_mode] == "disabled"
      assert opts[:seed] == 101
    end

    [[bridge_prompt, bridge_image, _] | segments] = i2v_calls
    assert bridge_image == "mock://prev.jpg"
    assert bridge_prompt =~ "stairwell"

    for {[prompt, _image, _opts], idx} <- Enum.with_index(segments) do
      assert prompt =~ "Continuation, part #{idx + 1} of 3."
    end
  end

  # CEL-05 (opening)
  test "opening generates a 720x1280 flux frame, then chained segments, no bridge" do
    {:ok, _pid} = Whn.Pipeline.start_opening(self(), ctx(%{beat: 0, winning_choice: nil}))

    assert_receive {:pipeline, 0, {:celeris, result}}, 10_000
    assert result.bridge == nil

    for idx <- 0..2 do
      assert_receive {:pipeline, 0, {:segment_ready, ^idx, _url}}, 10_000
    end

    refute_receive {:pipeline, _beat, {:bridge_ready, _url}}, 100

    assert [{:flux, [flux_prompt, flux_opts]}] =
             Enum.filter(Whn.FalMock.calls(), &match?({:flux, _}, &1))

    assert flux_opts[:image_size] == %{width: 720, height: 1280}
    assert flux_opts[:seed] == 100
    assert flux_prompt =~ "Salary enters"

    # first segment animates from the flux frame itself
    assert [[_prompt, "mock://flux-frame.png", _opts] | _] =
             for({:i2v, args} <- Whn.FalMock.calls(), do: args)
  end

  describe "VIDEO_ENGINE=omni" do
    setup do
      System.put_env("VIDEO_ENGINE", "omni")
      on_exit(fn -> System.delete_env("VIDEO_ENGINE") end)
      :ok
    end

    test "bridge is 15s as two chained clips, each sent as its own bridge_ready" do
      {:ok, _pid} = Whn.Pipeline.start_cycle(self(), ctx(%{last_frame_url: "mock://prev.jpg"}))

      assert_receive {:pipeline, 1, {:bridge_ready, first_url}}, 10_000
      assert_receive {:pipeline, 1, {:bridge_ready, second_url}}, 10_000
      assert is_binary(first_url) and is_binary(second_url)

      for expected_idx <- 0..2 do
        assert_receive {:pipeline, 1, {:segment_ready, idx, url}}, 10_000
        assert idx == expected_idx
        assert is_binary(url)
      end

      refute_receive {:pipeline, _beat, {:error, _stage, _reason}}, 100

      i2v_calls = for {:i2v, args} <- Whn.FalMock.calls(), do: args
      # bridge clip 1, bridge clip 2, then the three parallel segments
      assert length(i2v_calls) == 5
      assert [[_, clip1_image, clip1_opts], [_, clip2_image, clip2_opts] | _] = i2v_calls

      assert clip1_image == "mock://prev.jpg"
      assert clip1_opts[:duration] == 10
      # clip 2 chains from clip 1's extracted last frame, at 5s
      assert clip2_image =~ "mock://frame-"
      assert clip2_opts[:duration] == 5
    end

    test "scene segments fan out in parallel from one shared anchor frame" do
      {:ok, _pid} = Whn.Pipeline.start_cycle(self(), ctx(%{last_frame_url: "mock://prev.jpg"}))
      assert_receive {:pipeline, 1, {:segment_ready, 2, _url}}, 10_000

      segments =
        for {:i2v, [prompt, image, opts]} <- Whn.FalMock.calls(),
            prompt =~ "Continuation, part",
            do: {prompt, image, opts}

      assert length(segments) == 3

      # every segment animates from the same anchor: the extracted last
      # frame of the second bridge clip, not each other's frames
      anchors = for {_prompt, image, _opts} <- segments, do: image
      assert [anchor] = Enum.uniq(anchors)
      assert anchor =~ "mock://frame-"

      parts =
        for {prompt, _image, _opts} <- segments do
          [_, part] = Regex.run(~r/part (\d) of 3/, prompt)
          part
        end

      assert Enum.sort(parts) == ["1", "2", "3"]
      for {_prompt, _image, opts} <- segments, do: assert(opts[:duration] == 10)
    end

    test "opening fans out from the flux frame with no frame extraction" do
      {:ok, _pid} = Whn.Pipeline.start_opening(self(), ctx(%{beat: 0, winning_choice: nil}))

      for expected_idx <- 0..2 do
        assert_receive {:pipeline, 0, {:segment_ready, idx, _url}}, 10_000
        assert idx == expected_idx
      end

      refute_receive {:pipeline, _beat, {:bridge_ready, _url}}, 100

      anchors = for {:i2v, [_prompt, image, _opts]} <- Whn.FalMock.calls(), do: image
      assert anchors == List.duplicate("mock://flux-frame.png", 3)
      assert [] = for({:upload, args} <- Whn.FalMock.calls(), do: args)
    end
  end

  # CEL-06
  test "a failed segment retries once with identical args and never reports an error" do
    Whn.FalMock.fail_once(:i2v)

    # nil last_frame_url routes the bridge through t2v, so the first i2v is segment 0
    {:ok, _pid} = Whn.Pipeline.start_cycle(self(), ctx())

    for idx <- 0..2 do
      assert_receive {:pipeline, 1, {:segment_ready, ^idx, _url}}, 10_000
    end

    refute_receive {:pipeline, _beat, {:error, _stage, _reason}}, 100

    assert [[_prompt, t2v_opts]] = for({:t2v, args} <- Whn.FalMock.calls(), do: args)
    assert t2v_opts[:aspect_ratio] == "9:16"
    assert t2v_opts[:prompt_expansion_mode] == "balanced"

    i2v_calls = for {:i2v, args} <- Whn.FalMock.calls(), do: args
    # segment 0 twice (fail + identical retry), then segments 1 and 2
    assert length(i2v_calls) == 4
    assert [first_attempt, retry | _rest] = i2v_calls
    assert first_attempt == retry
  end
end

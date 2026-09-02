defmodule Whn.CelerisTest do
  # async: false — swaps the global :celeris app config for a Req.Test stub.
  use ExUnit.Case, async: false

  alias Whn.{Celeris, Prompts}

  @ctx %{
    beat: 3,
    seed: 42,
    episode: %{
      title: "Salary Just Entered",
      premise: "Salary enters and everyone wants a piece of it."
    },
    story_state: %{"money" => 180_000},
    winning_choice: "Pay the landlord half",
    last_frame_url: "https://example.com/frame.jpg",
    history: ["Salary landed and the phone immediately lit up."]
  }

  @valid %{
    "scene_summary" => "The landlord pockets half the salary, unimpressed.",
    "winning_choice" => "Pay the landlord half",
    "bridge" => %{
      "duration" => 9,
      "script" => "He counts the cash on the stairwell.",
      "video_prompt" =>
        "The protagonist counts cash while climbing a stairwell, stopping at a door."
    },
    "next_scene" => %{
      "duration" => 25,
      "script" => "The landlord wants the rest, and the phone will not stop ringing.",
      "video_prompt" =>
        "A landlord blocks a doorway, arms folded, while the protagonist gestures with a half-empty envelope."
    },
    "next_choices" => [
      "Hand over the rest",
      "Promise the balance next week",
      "Ask for a receipt first"
    ],
    "story_state_updates" => %{"money" => 90_000}
  }

  setup do
    System.put_env("CELERIS_TEST_KEY", "test-key")
    previous = Application.get_env(:whn, :celeris)

    Application.put_env(:whn, :celeris,
      key_env: "CELERIS_TEST_KEY",
      req_options: [plug: {Req.Test, Whn.Celeris}]
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:whn, :celeris, previous)
      else
        Application.delete_env(:whn, :celeris)
      end
    end)

    :ok
  end

  defp respond_with(content) do
    Req.Test.stub(Whn.Celeris, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => content}}]})
    end)
  end

  # CEL-01
  test "valid JSON yields all six fields, clamped per the contract" do
    respond_with(Jason.encode!(@valid))

    assert {:ok, result} = Celeris.run(@ctx)
    assert result.scene_summary == "The landlord pockets half the salary, unimpressed."
    assert result.winning_choice == "Pay the landlord half"
    assert result.bridge.duration == 9
    assert result.bridge.script == "He counts the cash on the stairwell."
    # next_scene duration is always forced to 30, whatever the model said
    assert result.next_scene.duration == 30
    assert result.next_choices == @valid["next_choices"]
    assert result.story_state_updates == %{"money" => 90_000}
  end

  test "request carries bearer auth, seed + beat, and the strict json_schema contract" do
    Req.Test.stub(Whn.Celeris, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]

      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(raw)

      assert body["model"] == "celeris-1"
      assert body["temperature"] == 0.6
      assert body["max_tokens"] == 700
      assert body["seed"] == 45
      assert [%{"role" => "system"}, %{"role" => "user"}] = body["messages"]
      assert get_in(body, ["response_format", "type"]) == "json_schema"
      assert get_in(body, ["response_format", "json_schema", "strict"]) == true
      assert get_in(body, ["response_format", "json_schema", "name"]) == "beat"

      schema = get_in(body, ["response_format", "json_schema", "schema"])
      assert get_in(schema, ["properties", "next_choices", "minItems"]) == 3
      assert get_in(schema, ["properties", "next_choices", "maxItems"]) == 3

      assert get_in(schema, ["properties", "bridge", "required"]) ==
               ["duration", "script", "video_prompt"]

      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => Jason.encode!(@valid)}}]})
    end)

    assert {:ok, _result} = Celeris.run(@ctx)
  end

  # CEL-02
  test "fenced JSON parses via brace-slice" do
    respond_with("```json\n" <> Jason.encode!(@valid) <> "\n```")

    assert {:ok, result} = Celeris.run(@ctx)
    assert result.bridge.video_prompt =~ "stairwell"
  end

  test "garbage twice falls back after exactly one retry, without raising" do
    counter = start_supervised!({Agent, fn -> 0 end})

    Req.Test.stub(Whn.Celeris, fn conn ->
      Agent.update(counter, &(&1 + 1))
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "no json here, sorry"}}]})
    end)

    assert {:ok, :fallback, result} = Celeris.run(@ctx)
    assert Agent.get(counter, & &1) == 2

    assert length(result.next_choices) == 3
    assert result.bridge.duration == 10
    assert result.next_scene.duration == 30
    # the generic bridge moves toward the consequence of the winning choice
    assert result.bridge.video_prompt =~ @ctx.winning_choice
    assert String.ends_with?(result.bridge.video_prompt, Prompts.vertical_suffix())
  end

  test "a missing video_prompt invalidates the reply and triggers the fallback" do
    broken = put_in(@valid["next_scene"]["video_prompt"], "")
    respond_with(Jason.encode!(broken))

    assert {:ok, :fallback, _result} = Celeris.run(@ctx)
  end

  # CEL-03
  test "system prompt carries the final-frame hygiene and wordless-audio rules" do
    system = Prompts.system_prompt()

    assert system =~ "FINAL FRAME HYGIENE"
    assert system =~ "readable"
    assert system =~ "wordless"
    assert system =~ "no spoken dialogue ever, in any language"
    assert system =~ "No quoted dialogue"
    assert system =~ "in English"
    assert system =~ "2D cartoon"
    assert Whn.Prompts.vertical_suffix() =~ "2D cartoon"

    assert Whn.Prompts.vertical_suffix() =~
             "No dialogue, no speech, no talking, no voices, silent characters"

    assert system =~ "Return ONLY compact JSON, no markdown fences, exactly this shape:"
  end

  test "both returned video_prompts end with the vertical suffix" do
    respond_with(Jason.encode!(@valid))

    assert {:ok, result} = Celeris.run(@ctx)
    assert String.ends_with?(result.bridge.video_prompt, Prompts.vertical_suffix())
    assert String.ends_with?(result.next_scene.video_prompt, Prompts.vertical_suffix())
  end

  test "all quoted dialogue is stripped from both prompts" do
    raw =
      put_in(
        @valid,
        ["next_scene", "video_prompt"],
        ~s(Tunde pleads. Tunde says: "I am not running anywhere, sir." The landlord grunts. Landlord says: "extra line that must go" He waits.)
      )
      |> put_in(
        ["bridge", "video_prompt"],
        ~s(Tunde walks out. Tunde says: "this should never survive in a bridge" He hails a bus.)
      )

    respond_with(Jason.encode!(raw))
    assert {:ok, result} = Celeris.run(@ctx)

    scene = result.next_scene.video_prompt
    refute scene =~ "\""
    refute scene =~ "not running anywhere"
    refute scene =~ "extra line"
    assert scene =~ "Tunde pleads."
    assert scene =~ "He waits."

    refute result.bridge.video_prompt =~ "\""
    refute result.bridge.video_prompt =~ "never survive"
    assert result.bridge.video_prompt =~ "He hails a bus."
  end

  test "SCRIPT_ENGINE=gemini routes through the fal vision route with the same prompts" do
    defmodule VisionStub do
      @behaviour Whn.Fal
      def t2v(_p, _o), do: {:error, :unused}
      def i2v(_p, _i, _o), do: {:error, :unused}
      def flux(_p, _o), do: {:error, :unused}
      def upload(_p), do: {:error, :unused}

      def vision(prompt, opts) do
        send(self(), {:vision_called, prompt, opts})

        valid = %{
          "scene_summary" => "Gemini wrote this beat.",
          "winning_choice" => "Pay the landlord half",
          "bridge" => %{"duration" => 10, "script" => "s", "video_prompt" => "He walks out."},
          "next_scene" => %{
            "duration" => 30,
            "script" => "s",
            "video_prompt" => "The argument continues."
          },
          "next_choices" => ["A real option", "Another option", "A third option"],
          "story_state_updates" => %{}
        }

        {:ok, %{output: Jason.encode!(valid)}}
      end
    end

    previous = Application.get_env(:whn, :fal_impl)
    Application.put_env(:whn, :fal_impl, VisionStub)
    System.put_env("SCRIPT_ENGINE", "gemini")

    on_exit(fn ->
      System.delete_env("SCRIPT_ENGINE")

      if previous,
        do: Application.put_env(:whn, :fal_impl, previous),
        else: Application.delete_env(:whn, :fal_impl)
    end)

    assert {:ok, result} = Celeris.run(@ctx)
    assert result.scene_summary == "Gemini wrote this beat."

    assert_receive {:vision_called, prompt, opts}
    assert prompt =~ "Salary Just Entered"
    assert opts[:model] == "google/gemini-2.5-flash-lite"
    assert opts[:system_prompt] =~ "FINAL FRAME HYGIENE"
    assert opts[:max_tokens] == 700
  end

  test "user prompt renders state and choice, or the opening instruction when choice is nil" do
    prompt = Prompts.user_prompt(@ctx)
    assert prompt =~ "Salary Just Entered"
    assert prompt =~ "Pay the landlord half"
    assert prompt =~ "money"

    opening = Prompts.user_prompt(%{@ctx | winning_choice: nil})
    assert opening =~ "OPENING — establish the premise and first decision"
  end
end

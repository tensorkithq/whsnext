defmodule Whn.Fal.OmniImplTest do
  use ExUnit.Case, async: true

  alias Whn.Fal.OmniImpl

  # The pipeline passes the same opts it passes h3-max; omni's schema is
  # narrower, so the impl must rebuild the input rather than pass through.

  test "t2v input maps h3-max opts onto omni's schema" do
    input =
      OmniImpl.t2v_input("a street scene",
        duration: 10,
        resolution: "480P",
        aspect_ratio: "9:16",
        prompt_expansion_mode: "balanced",
        seed: 42
      )

    assert input == %{
             prompt: "a street scene",
             duration: 10,
             resolution: "360p",
             aspect_ratio: "9:16"
           }
  end

  test "i2v input carries the first frame and drops unsupported params" do
    input =
      OmniImpl.i2v_input("continue the scene", "hosted://frame.jpg",
        duration: 5,
        resolution: "480P",
        prompt_expansion_mode: "disabled",
        seed: 7
      )

    assert input == %{
             prompt: "continue the scene",
             duration: 5,
             resolution: "360p",
             image_url: "hosted://frame.jpg"
           }

    refute Map.has_key?(input, :seed)
    refute Map.has_key?(input, :prompt_expansion_mode)
  end

  test "duration clamps to omni's 10s cap and is omitted when absent" do
    assert %{duration: 10} = OmniImpl.i2v_input("p", "hosted://f.jpg", duration: 12)
    refute Map.has_key?(OmniImpl.t2v_input("p", []), :duration)
  end
end

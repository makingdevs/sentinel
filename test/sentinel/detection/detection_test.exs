defmodule Sentinel.DetectionTest do
  use ExUnit.Case, async: true
  alias Sentinel.Detection

  test "filters classes and invalid boxes, clips coordinates and caps output" do
    person = %{"class_id" => 0, "confidence" => 0.8, "xyxy" => [-10, -20, 80, 90]}
    car = %{"class_id" => 2, "confidence" => 0.7, "xyxy" => [50, 40, 500, 300]}

    ignored = [
      %{person | "class_id" => 1},
      %{person | "confidence" => 0.1},
      %{person | "xyxy" => [50, 50, 10, 10]},
      %{"class_id" => 0}
    ]

    assert [first, second] = Detection.normalize([person, car | ignored], 100, 80)
    assert first.class == "Persona"
    assert first.bbox == %{cx: 40.0, cy: 40.0, w: 80, h: 80}
    assert second.class == "Auto"
    assert second.bbox == %{cx: 75.0, cy: 60.0, w: 50, h: 40}
    assert length(Detection.normalize(List.duplicate(person, 1000), 100, 100)) == 100
  end

  test "engine input never creates atoms" do
    assert Detection.valid_engine?("python")
    assert Detection.valid_engine?("elixir")
    refute Detection.valid_engine?("../../command")
    refute Detection.available?("anything")
  end

  test "RGB preprocessing preserves red rather than swapping to blue" do
    image = Image.new!(2, 2, color: [255, 0, 0])
    model = %{shapes: %{input: {1, 3, 2, 2}}}
    {tensor, _} = Sentinel.Detection.UltralyticsModel.preprocess(model, image, [])
    assert [red, green, blue] = tensor |> Nx.to_flat_list() |> Enum.chunk_every(4)
    assert Enum.all?(red, &(&1 == 1.0))
    assert Enum.all?(green ++ blue, &(&1 == 0.0))
  end
end

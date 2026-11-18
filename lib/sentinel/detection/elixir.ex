defmodule Sentinel.Detection.Elixir do
  @moduledoc "YOLO/Ortex backend using the same YOLO11n weights as Python."
  @behaviour Sentinel.Detection.Adapter
  alias Sentinel.Detection

  @impl true
  def load do
    model =
      YOLO.load(
        model_path: Detection.model("onnx"),
        model_impl: Sentinel.Detection.UltralyticsModel,
        eps: [:cpu],
        json_decoder: &Jason.decode!/1
      )

    {:ok, model}
  end

  @impl true
  def infer(model, frame) do
    format = %Membrane.RawVideo{
      width: frame.width,
      height: frame.height,
      pixel_format: :RGB,
      framerate: {0, 1},
      aligned: true
    }

    {:ok, image} = Membrane.RawVideo.payload_to_image(frame.payload, format)

    objects =
      model
      |> YOLO.detect(image, prob_threshold: 0.35, iou_threshold: 0.45)
      |> Enum.flat_map(fn
        [cx, cy, w, h, prob, class] when class in [0, 0.0, 2, 2.0] ->
          [
            %{
              "class_id" => round(class),
              "confidence" => prob,
              "xyxy" => [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]
            }
          ]

        _ ->
          []
      end)

    {:ok, objects}
  end

  @impl true
  def close(_model), do: :ok
end

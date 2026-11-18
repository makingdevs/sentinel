defmodule Sentinel.Detection do
  @moduledoc "Configuration and validated, pixel-coordinate detections shared by both engines."

  @engines ~w(off python elixir)
  def engines, do: @engines
  def valid_engine?(engine), do: engine in @engines

  def validate_engine(engine),
    do: if(valid_engine?(engine), do: :ok, else: {:error, :unknown_engine})

  def config, do: Application.get_env(:sentinel, :detection, [])
  def get(key, default), do: Keyword.get(config(), key, default)

  def available?("off"), do: true
  def available?("python"), do: File.exists?(python()) and File.exists?(model("pt"))
  def available?("elixir"), do: File.exists?(model("onnx"))
  def available?(_), do: false
  def python, do: get(:python, Path.expand(".venv/bin/python"))

  def model(extension),
    do: Path.join(get(:model_directory, Path.expand("models")), "yolo11n.#{extension}")

  def normalize(objects, width, height) when is_list(objects) do
    objects
    |> Enum.take(100)
    |> Enum.flat_map(&normalize_object(&1, width, height))
  end

  def normalize(_, _, _), do: []

  defp normalize_object(
         %{"class_id" => class, "confidence" => prob, "xyxy" => [x1, y1, x2, y2]},
         w,
         h
       )
       when class in [0, 2] and is_number(prob) and prob >= 0.35 and prob <= 1 and
              is_number(x1) and is_number(y1) and is_number(x2) and is_number(y2) do
    left = min(max(round(x1), 0), w - 1)
    top = min(max(round(y1), 0), h - 1)
    right = min(max(round(x2), 0), w)
    bottom = min(max(round(y2), 0), h)

    if right > left and bottom > top do
      [
        %{
          class_idx: class,
          class: if(class == 0, do: "Persona", else: "Auto"),
          prob: prob,
          bbox: %{
            cx: (left + right) / 2,
            cy: (top + bottom) / 2,
            w: right - left,
            h: bottom - top
          }
        }
      ]
    else
      []
    end
  end

  defp normalize_object(_, _, _), do: []
end

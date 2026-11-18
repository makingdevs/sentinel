defmodule Sentinel.Detection.UltralyticsModel do
  @moduledoc "Ultralytics RGB preprocessing. The upstream Image scaler otherwise reverses RGB channels."
  @behaviour YOLO.Model
  import Nx.Defn

  @impl true
  def init(model, _opts), do: model

  @impl true
  def preprocess(model, image, _opts) do
    {_, _, height, width} = model.shapes.input

    {tensor, scaling} =
      YOLO.FrameScalers.fit(image, {height, width}, YOLO.FrameScalers.ImageScaler)

    input = normalize_rgb(tensor)
    {input, scaling}
  end

  defnp normalize_rgb(tensor) do
    tensor
    |> Nx.as_type(:f32)
    |> Nx.divide(255)
    |> Nx.transpose(axes: [2, 0, 1])
    |> Nx.new_axis(0)
  end

  @impl true
  defdelegate postprocess(model, output, scaling, opts), to: YOLO.Models.Ultralytics
end

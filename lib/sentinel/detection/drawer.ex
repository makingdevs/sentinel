defmodule Sentinel.Detection.Drawer do
  @moduledoc "Rasterizes labels once per detection result, then composites one cached overlay per frame."
  use Membrane.Filter

  def_input_pad(:input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})
  def_output_pad(:output, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})

  @impl true
  def handle_init(_ctx, _opts), do: {[], %{objects: nil, overlay: nil, format: nil}}

  @impl true
  def handle_stream_format(:input, format, _ctx, _state) do
    {[stream_format: {:output, format}], %{objects: nil, overlay: nil, format: format}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    objects = Map.get(buffer.metadata, :detected_objects, [])
    {payload, state} = render(buffer.payload, objects, state)
    {[buffer: {:output, %{buffer | payload: payload}}], state}
  end

  @doc false
  def render(payload, [], state), do: {payload, %{state | objects: [], overlay: nil}}

  def render(payload, objects, state) do
    overlay = if state.objects == objects, do: state.overlay, else: overlay(objects, state.format)
    {:ok, image} = Membrane.RawVideo.payload_to_image(payload, state.format)
    image = image |> Image.compose!(overlay, x: 0, y: 0) |> Image.split_alpha() |> elem(0)
    {:ok, output, _format} = Membrane.RawVideo.image_to_payload(image)
    {output, %{state | objects: objects, overlay: overlay}}
  end

  defp overlay(objects, format) do
    drawings =
      Enum.map_join(objects, fn object ->
        %{cx: cx, cy: cy, w: w, h: h} = object.bbox
        x = max(0, round(cx - w / 2))
        y = max(0, round(cy - h / 2))
        color = if object.class_idx == 0, do: "#5eead4", else: "#fbbf24"
        label = if object.class_idx == 0, do: "Persona", else: "Auto"
        text = "#{label} #{round(object.prob * 100)}%"
        label_width = min(format.width, 12 + String.length(text) * 7)
        label_x = min(x, format.width - label_width)
        label_y = max(0, y - 20)

        ~s(<rect x="#{x}" y="#{y}" width="#{w}" height="#{h}" fill="none" stroke="#{color}" stroke-width="2"/><rect x="#{label_x}" y="#{label_y}" width="#{label_width}" height="19" rx="3" fill="#{color}"/><text x="#{label_x + 5}" y="#{label_y + 13}" font-family="sans-serif" font-size="12" font-weight="600" fill="#020617">#{text}</text>)
      end)

    svg =
      ~s(<svg xmlns="http://www.w3.org/2000/svg" width="#{format.width}" height="#{format.height}">#{drawings}</svg>)

    # Materialize the cached raster so no SVG operation is re-evaluated for later frames.
    {:ok, overlay} = svg |> Image.from_svg!() |> Vix.Vips.Image.copy_memory()
    overlay
  end
end

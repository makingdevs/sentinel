Mix.Task.run("app.config")
Application.load(:sentinel)
for app <- Application.spec(:sentinel, :applications), do: Application.ensure_all_started(app)
Logger.configure(level: :error)
root = "tmp/detection-fixtures/000.rgb"
%{"width" => w, "height" => h} = Jason.decode!(File.read!(root <> ".json"))
payload = File.read!(root)

format = %Membrane.RawVideo{
  width: w,
  height: h,
  framerate: {25, 1},
  pixel_format: :RGB,
  aligned: true
}

result =
  Jason.decode!(File.read!("tmp/detection-python.json"))
  |> Map.fetch!("results")
  |> Enum.find(&(&1["file"] == "000.rgb"))

objects =
  for object <- result["objects"] do
    bbox =
      Map.new(object["bbox"], fn {key, value} ->
        {case key do
           "cx" -> :cx
           "cy" -> :cy
           "w" -> :w
           "h" -> :h
         end, value}
      end)

    %{bbox: bbox, class_idx: object["class_idx"], class: object["class"], prob: object["prob"]}
  end

measure = fn mode ->
  {times, _} =
    Enum.map_reduce(1..100, %{format: format, objects: nil, overlay: nil}, fn index, state ->
      # Every fifth frame has a new set of boxes, approximating 5Hz inference /25Hz video.
      boxes =
        Enum.map(objects, fn object ->
          put_in(object.bbox.cx, object.bbox.cx + rem(div(index, 5), 2))
        end)

      start = System.monotonic_time(:microsecond)

      state =
        if mode != :original do
          state = if mode == :uncached_svg, do: %{state | objects: nil, overlay: nil}, else: state
          {_output, state} = Sentinel.Detection.Drawer.render(payload, boxes, state)
          state
        else
          {:ok, image} = Membrane.RawVideo.payload_to_image(payload, format)
          image = Membrane.YOLO.Drawer.DrawUtils.draw_detected_objects(image, boxes)
          {:ok, _payload, _format} = Membrane.RawVideo.image_to_payload(image)
          state
        end

      {System.monotonic_time(:microsecond) - start, state}
    end)

  sorted = Enum.sort(times)

  %{
    mode: mode,
    frames: 100,
    objects: length(objects),
    p50_ms: Enum.at(sorted, 50) / 1000,
    p95_ms: Enum.at(sorted, 95) / 1000,
    total_ms: Enum.sum(times) / 1000
  }
end

results = [measure.(:original), measure.(:uncached_svg), measure.(:cached)]
File.write!("tmp/detection-render-profile.json", Jason.encode!(results, pretty: true))
IO.puts(Jason.encode!(results))

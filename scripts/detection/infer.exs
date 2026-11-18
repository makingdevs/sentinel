Mix.Task.run("app.config")
Application.load(:sentinel)
for app <- Application.spec(:sentinel, :applications), do: Application.ensure_all_started(app)
Logger.configure(level: :error)
[engine, directory, output] = System.argv()

adapter =
  case engine do
    "python" -> Sentinel.Detection.Python
    "elixir" -> Sentinel.Detection.Elixir
  end

{:ok, model} = adapter.load()
files = Path.wildcard(Path.join(directory, "*.rgb")) |> Enum.sort()

results =
  for file <- files do
    %{"width" => w, "height" => h} = Jason.decode!(File.read!(file <> ".json"))
    frame = %{width: w, height: h, frame_id: Path.basename(file), payload: File.read!(file)}
    start = System.monotonic_time(:microsecond)
    {:ok, objects} = adapter.infer(model, frame)
    duration = System.monotonic_time(:microsecond) - start
    objects = Sentinel.Detection.normalize(objects, w, h)

    {:ok, image} =
      Membrane.RawVideo.payload_to_image(frame.payload, %Membrane.RawVideo{
        width: w,
        height: h,
        framerate: {0, 1},
        pixel_format: :RGB,
        aligned: true
      })

    {payload, _state} =
      Sentinel.Detection.Drawer.render(frame.payload, objects, %{
        format: %Membrane.RawVideo{
          width: w,
          height: h,
          framerate: {0, 1},
          pixel_format: :RGB,
          aligned: true
        },
        objects: nil,
        overlay: nil
      })

    {:ok, image} =
      Membrane.RawVideo.payload_to_image(payload, %Membrane.RawVideo{
        width: w,
        height: h,
        framerate: {0, 1},
        pixel_format: :RGB,
        aligned: true
      })

    Image.write!(image, file <> ".#{engine}.jpg")
    %{file: Path.basename(file), duration_us: duration, objects: objects}
  end

adapter.close(model)
File.write!(output, Jason.encode!(%{engine: engine, results: results}, pretty: true))

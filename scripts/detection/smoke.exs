Process.flag(:trap_exit, true)
Mix.Task.run("app.config")
Application.load(:sentinel)
for app <- Application.spec(:sentinel, :applications), do: Application.ensure_all_started(app)
Logger.configure(level: :error)
:logger.add_primary_filter(:sentinel_rtsp, {&Sentinel.Monitoring.LogFilter.filter/2, []})

{:ok, _} =
  DynamicSupervisor.start_link(
    strategy: :one_for_one,
    name: Sentinel.Detection.Supervisor,
    max_children: 8
  )

path = System.get_env("CAMERA_RTSP_SOURCES_FILE", "tmp/camera_rtsp_sources.json")
sources = Jason.decode!(File.read!(path))
id = System.get_env("DETECTION_CAMERA", sources |> Map.keys() |> Enum.sort() |> hd())
quality = System.get_env("DETECTION_QUALITY", "secundaria")
url = sources |> Map.fetch!(id) |> Map.fetch!(quality)
engines = System.argv()
engines = if engines == [], do: ["off", "python", "elixir"], else: engines

results =
  for engine <- engines do
    directory = Path.expand("tmp/detection-smoke/#{engine}")
    File.mkdir_p!(directory)
    generation = Integer.to_string(System.unique_integer([:positive]))

    {:ok, _sup, pipeline} =
      Sentinel.Monitoring.Pipeline.start(%{
        source_url: url,
        owner: self(),
        directory: directory,
        generation: generation,
        engine: engine
      })

    deadline = System.monotonic_time(:millisecond) + 35_000

    collect = fn collect, states ->
      remaining = max(0, deadline - System.monotonic_time(:millisecond))

      receive do
        {:EXIT, ^pipeline, _reason} -> Enum.reverse([:pipeline_exited | states])
        {:pipeline_ready, ^pipeline} -> collect.(collect, [:hls_ready | states])
        {:detection_status, ^pipeline, status} -> collect.(collect, [status | states])
        {:pipeline_error, ^pipeline, reason} -> collect.(collect, [reason | states])
      after
        remaining -> Enum.reverse(states)
      end
    end

    states = collect.(collect, [])
    if Process.info(pipeline), do: Sentinel.Monitoring.Pipeline.stop(pipeline)

    result = %{
      engine: engine,
      states: states,
      segments: length(Path.wildcard(directory <> "/*.m4s")),
      directory: directory
    }

    IO.puts(Jason.encode!(result))
    File.write!(directory <> "/result.json", Jason.encode!(result, pretty: true))
    result
  end

unless Enum.all?(results, fn result ->
         :hls_ready in result.states and (result.engine == "off" or :active in result.states)
       end) do
  System.halt(1)
end

Supervisor.stop(Sentinel.Detection.Supervisor, :normal, 130_000)

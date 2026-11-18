Process.flag(:trap_exit, true)
Mix.Task.run("app.config")
Application.load(:sentinel)
for app <- Application.spec(:sentinel, :applications), do: Application.ensure_all_started(app)
Logger.configure(level: :error)
Code.require_file("fixture_pipeline.exs", __DIR__)

{:ok, _} =
  DynamicSupervisor.start_link(
    strategy: :one_for_one,
    name: Sentinel.Detection.Supervisor,
    max_children: 8
  )

[engine, count, duration, repetition, output] = System.argv()
count = String.to_integer(count)
duration = String.to_integer(duration)
codec = System.get_env("DETECTION_FIXTURE_CODEC", "H264")
fixture = Path.expand("tmp/detection-fixtures/workshop.#{String.downcase(codec)}")
File.mkdir_p!(output)
owner = self()

:telemetry.attach_many(
  "benchmark",
  [
    [:sentinel, :detection, :inference],
    [:sentinel, :detection, :frame],
    [:sentinel, :benchmark, :output],
    [:sentinel, :detection, :video_drop]
  ],
  fn event, measurements, metadata, pid ->
    send(pid, {:metric, event, measurements, metadata})
  end,
  owner
)

opts =
  for index <- 1..count do
    directory = Path.join(output, "stream-#{index}")
    File.mkdir_p!(directory)

    %{
      file: fixture,
      codec: codec,
      engine: engine,
      owner: self(),
      generation: "bench_#{index}",
      directory: directory,
      started_ms: System.monotonic_time(:millisecond)
    }
  end

pipelines =
  for opt <- opts do
    {:ok, _sup, pipeline} = Membrane.Pipeline.start_link(Sentinel.Detection.FixturePipeline, opt)
    pipeline
  end

# Exclude initial model loading/JIT and include the same fixture time interval for both engines.
started = System.monotonic_time(:millisecond)
warmup = 10_000
finish = started + warmup + duration * 1000

collect = fn collect, acc ->
  remaining = max(0, finish - System.monotonic_time(:millisecond))

  receive do
    {:metric, [:sentinel, :detection, :video_drop], m, _} ->
      if System.monotonic_time(:millisecond) >= started + warmup,
        do: collect.(collect, %{acc | video_drops: acc.video_drops + m.frames}),
        else: collect.(collect, acc)

    {:metric, [:sentinel, :benchmark, :output], m, _} ->
      if System.monotonic_time(:millisecond) >= started + warmup,
        do: collect.(collect, %{acc | outputs: acc.outputs + 1, lags: [m.lag_ms | acc.lags]}),
        else: collect.(collect, acc)

    {:metric, [:sentinel, :detection, :inference], m, _} ->
      if System.monotonic_time(:millisecond) >= started + warmup,
        do:
          collect.(collect, %{
            acc
            | durations: [m.duration_us | acc.durations],
              objects: acc.objects + m.objects
          }),
        else: collect.(collect, acc)

    {:metric, [:sentinel, :detection, :frame], m, meta} ->
      if System.monotonic_time(:millisecond) >= started + warmup do
        last_pts = Map.put(acc.last_pts, meta.generation, m.pts)
        first_pts = Map.put_new(acc.first_pts, meta.generation, m.pts)

        collect.(collect, %{
          acc
          | frames: acc.frames + 1,
            dropped: acc.dropped + m.dropped,
            boxed: acc.boxed + m.boxed,
            ages: if(m.boxed > 0, do: [m.box_age_ms | acc.ages], else: acc.ages),
            last_pts: last_pts,
            first_pts: first_pts
        })
      else
        collect.(collect, acc)
      end

    {:detection_status, _pid, status} ->
      collect.(collect, %{acc | states: [status | acc.states]})

    {:pipeline_ready, pid} ->
      collect.(collect, %{acc | ready: MapSet.put(acc.ready, pid)})

    {:EXIT, pid, _} ->
      collect.(collect, if(pid in pipelines, do: %{acc | exits: acc.exits + 1}, else: acc))

    _ ->
      collect.(collect, acc)
  after
    remaining -> acc
  end
end

acc =
  collect.(collect, %{
    video_drops: 0,
    outputs: 0,
    lags: [],
    durations: [],
    frames: 0,
    dropped: 0,
    boxed: 0,
    ages: [],
    objects: 0,
    states: [],
    ready: MapSet.new(),
    exits: 0,
    first_pts: %{},
    last_pts: %{}
  })

# Capture files before terminating; terminate flushes the muxer and worker children.
for pipeline <- pipelines,
    Process.info(pipeline) != nil,
    do: Membrane.Pipeline.terminate(pipeline, force?: true, timeout: 5_000)

# Wait for in-flight dirty NIFs/Ports before the VM exits. Killing the pipeline
# alone leaves owner-monitored workers alive for a short interval.
Supervisor.stop(Sentinel.Detection.Supervisor, :normal, 130_000)

percentile = fn values, fraction ->
  case Enum.sort(values) do
    [] -> nil
    sorted -> Enum.at(sorted, min(length(sorted) - 1, floor(length(sorted) * fraction)))
  end
end

result = %{
  engine: engine,
  streams: count,
  repetition: String.to_integer(repetition),
  seconds: duration,
  warmup_seconds: 10,
  inference_count: length(acc.durations),
  inference_p50_ms: if(acc.durations != [], do: percentile.(acc.durations, 0.5) / 1000),
  inference_p95_ms: if(acc.durations != [], do: percentile.(acc.durations, 0.95) / 1000),
  inference_fps_total: length(acc.durations) / duration,
  input_frames: acc.frames,
  output_fps_per_stream: acc.outputs / duration / count,
  pipeline_lag_p95_ms: percentile.(acc.lags, 0.95),
  video_drops: acc.video_drops,
  pending_replacements: acc.dropped,
  boxed_frames: acc.boxed,
  box_age_p95_ms: percentile.(acc.ages, 0.95),
  detected_objects: acc.objects,
  states: Enum.frequencies(acc.states),
  hls_ready: MapSet.size(acc.ready),
  exits: acc.exits,
  beam_memory_bytes: :erlang.memory(:total),
  codec: codec,
  media_seconds:
    Enum.map(acc.last_pts, fn {key, pts} ->
      (pts - Map.fetch!(acc.first_pts, key)) / 1_000_000_000
    end),
  segments: Enum.map(opts, fn opt -> length(Path.wildcard(opt.directory <> "/*.m4s")) end)
}

File.write!(Path.join(output, "result.json"), Jason.encode!(result, pretty: true))
IO.puts(Jason.encode!(result))

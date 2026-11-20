# Private camera URLs are resolved only in Monitoring; no configuration/rule writes.
Mix.Task.run("app.config")
Application.load(:sentinel)
for app <- Application.spec(:sentinel, :applications), do: Application.ensure_all_started(app)
Logger.configure(level: :critical)
:logger.add_primary_filter(:sentinel_rtsp, {&Sentinel.Monitoring.LogFilter.filter/2, []})

Application.put_env(:sentinel, :visitor_counting,
  start_manager: false,
  primary_snapshots: true,
  primary_snapshot_cameras: :all
)

owner = self()
metrics = :ets.new(:capture_smoke_ingress, [:public, :set])

:telemetry.attach(
  :capture_smoke_ingress,
  [:sentinel, :visitor_counting, :ingress],
  fn _, values, meta, table ->
    :ets.update_counter(
      table,
      {meta.camera_id, meta.channel},
      {2, values.bytes},
      {{meta.camera_id, meta.channel}, 0}
    )
  end,
  metrics
)

children = [
  Sentinel.Repo,
  {Phoenix.PubSub, name: Sentinel.PubSub},
  {DynamicSupervisor,
   name: Sentinel.Detection.Supervisor, strategy: :one_for_one, max_children: 8},
  {Registry, keys: :unique, name: Sentinel.VisitorCounting.Registry},
  {Registry, keys: :unique, name: Sentinel.VisitorCounting.SnapshotRegistry},
  {DynamicSupervisor, name: Sentinel.VisitorCounting.SnapshotSources, strategy: :one_for_one},
  {Sentinel.VisitorCounting.Writer,
   persist: fn event ->
     send(
       owner,
       {:admitted_capture,
        Map.take(event.attrs, [:snapshot_quality, :snapshot_width, :snapshot_height])}
     )

     {:ok, %{id: 0}, :existing}
   end},
  {DynamicSupervisor, name: Sentinel.VisitorCounting.Cameras, strategy: :one_for_one}
]

{:ok, supervisor} = Supervisor.start_link(children, strategy: :one_for_one)

ids =
  case System.argv() do
    [] -> Sentinel.Monitoring.list_cameras() |> Enum.take(2) |> Enum.map(& &1.id)
    ids -> Enum.take(ids, 2)
  end

cameras =
  Enum.map(ids, fn id ->
    rule = Sentinel.VisitorCounting.get_rule(id) || %Sentinel.VisitorCounting.Rule{camera_id: id}

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Sentinel.VisitorCounting.Cameras,
        {Sentinel.VisitorCounting.Camera, rule: rule}
      )

    {id, pid}
  end)

started = System.monotonic_time(:millisecond)
deadline = started + 55_000
Process.send_after(self(), :measure, 1_000)

collect = fn collect, samples, captures, disrupted ->
  receive do
    :measure ->
      now = System.monotonic_time(:millisecond)

      stats =
        Enum.map(cameras, fn {id, pid} ->
          state = :sys.get_state(pid)

          cache =
            case Sentinel.VisitorCounting.SnapshotSource.read(id) do
              {:ok, cache} -> cache
              _ -> %{frames: [], bytes: 0, reason: "unavailable"}
            end

          latest = List.first(cache.frames)

          %{
            camera_id: id,
            secondary_session: state.session,
            secondary_status: state.status,
            encoded_ingress_bytes:
              Map.new([:primary, :secondary], fn channel ->
                case :ets.lookup(metrics, {id, channel}) do
                  [{_, bytes}] -> {channel, bytes}
                  [] -> {channel, 0}
                end
              end),
            secondary_frames: state.metrics.frames,
            primary_frames: length(cache.frames),
            primary_bytes: cache.bytes,
            primary_dimensions: if(latest, do: [latest.width, latest.height]),
            primary_receipt_age_ms: if(latest, do: now - latest.received_mono),
            cache_reason: cache.reason,
            source_mailbox:
              case Registry.lookup(Sentinel.VisitorCounting.SnapshotRegistry, id) do
                [{source, _}] -> elem(Process.info(source, :message_queue_len), 1)
                [] -> 0
              end
          }
        end)

      {ps, 0} = System.cmd("ps", ["-p", System.pid(), "-o", "%cpu=,rss="])

      sample = %{
        elapsed_ms: now - started,
        process_cpu_percent_and_rss_kib: String.trim(ps),
        cameras: stats
      }

      disrupted =
        if not disrupted and now - started > 30_000 do
          for {id, _} <- cameras do
            [{source, _}] = Registry.lookup(Sentinel.VisitorCounting.SnapshotRegistry, id)
            state = :sys.get_state(source)
            if state.pipeline, do: Sentinel.VisitorCounting.SnapshotPipeline.stop(state.pipeline)
          end

          true
        else
          disrupted
        end

      if now < deadline do
        Process.send_after(self(), :measure, 1_000)
        collect.(collect, [sample | samples], captures, disrupted)
      else
        {Enum.reverse([sample | samples]), captures}
      end

    {:admitted_capture, metadata} ->
      collect.(collect, samples, [metadata | captures], disrupted)
  after
    60_000 -> raise "Capture smoke timed out"
  end
end

try do
  {samples, captures} = collect.(collect, [], [], false)

  first =
    Enum.find(samples, fn sample ->
      Enum.all?(sample.cameras, &(&1.secondary_frames > 0 and &1.primary_frames > 0))
    end)

  last = List.last(samples)

  pass =
    first != nil and
      Enum.all?(last.cameras, fn camera ->
        initial = Enum.find(first.cameras, &(&1.camera_id == camera.camera_id))

        camera.secondary_session == initial.secondary_session and
          camera.secondary_frames > initial.secondary_frames and camera.primary_frames > 0 and
          camera.primary_bytes <= 12 * 1024 * 1024
      end)

  result = %{
    passed: pass,
    samples: samples,
    admitted_captures: captures,
    persisted_events: 0,
    rule_writes: 0,
    exposure_skew: "Not sensor synchronized; receipt ages only"
  }

  File.mkdir_p!("tmp/visitor-capture-smoke")
  File.write!("tmp/visitor-capture-smoke/result.json", Jason.encode!(result, pretty: true))

  IO.puts(
    Jason.encode!(%{
      passed: pass,
      first_healthy: first,
      final: last,
      evidence: "tmp/visitor-capture-smoke/result.json"
    })
  )

  if not pass, do: System.halt(1)
after
  Supervisor.stop(supervisor, :normal, 130_000)
end

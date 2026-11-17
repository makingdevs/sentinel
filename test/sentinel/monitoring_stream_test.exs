defmodule Sentinel.MonitoringStreamTest do
  use ExUnit.Case, async: false

  alias Sentinel.Monitoring
  alias Sentinel.Monitoring.Stream, as: CameraStream

  setup do
    config = Monitoring.config()

    directory =
      Path.join(System.tmp_dir!(), "sentinel-media-#{System.unique_integer([:positive])}")

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    Application.put_env(:sentinel, :media_test_owner, self())

    Application.put_env(
      :sentinel,
      :monitoring,
      Keyword.merge(config,
        hls_directory: directory,
        pipeline_module: Sentinel.TestMediaPipeline,
        sources: %{"division-1" => %{"secundaria" => "rtsp://example.test/video"}}
      )
    )

    on_exit(fn ->
      for {pid, _} <- Registry.lookup(Sentinel.Monitoring.Registry, {"division-1", "secundaria"}) do
        DynamicSupervisor.terminate_child(Sentinel.Monitoring.Supervisor, pid)
      end

      Application.put_env(:sentinel, :monitoring, config)
      Application.delete_env(:sentinel, :media_test_owner)
      File.rm_rf!(directory)
    end)

    {:ok, directory: directory}
  end

  test "concurrent readers share one pipeline and read complete HLS resources" do
    results =
      Task.async_stream(1..8, fn _ ->
        Monitoring.media_file("division-1", "secundaria", "index.m3u8")
      end)
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:error, :warming_up}}, &1))
    assert_receive {:media_started, media, options}
    refute_received {:media_started, _, _}
    File.write!(Path.join(options.directory, "index.m3u8"), "#EXTM3U\n")
    send(options.owner, {:pipeline_ready, media})
    _ = :sys.get_state(options.owner)
    assert {:ok, "#EXTM3U\n"} = Monitoring.media_file("division-1", "secundaria", "index.m3u8")
    assert {:error, :enoent} = Monitoring.media_file("division-1", "secundaria", "missing.m4s")
  end

  test "idle conversion releases the pipeline and its owned files", %{directory: root} do
    pid =
      start_supervised!(
        {CameraStream,
         key: {"idle-camera", "secundaria"},
         source_url: "rtsp://example.test/video",
         directory: root,
         pipeline_module: Sentinel.TestMediaPipeline,
         idle_ms: 100}
      )

    ref = Process.monitor(pid)
    assert_receive {:media_started, media, options}
    media_ref = Process.monitor(media)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    assert_receive {:DOWN, ^media_ref, :process, ^media, :normal}, 2_000
    refute File.exists?(options.directory)
  end

  test "a source that stops producing segments is closed by the watchdog", %{directory: root} do
    worker =
      start_supervised!(
        {CameraStream,
         key: {"stalled-camera", "secundaria"},
         source_url: "rtsp://example.test/video",
         directory: root,
         pipeline_module: Sentinel.TestMediaPipeline,
         idle_ms: 10_000,
         stall_ms: 100}
      )

    assert_receive {:media_started, media, _options}
    ref = Process.monitor(media)
    send(worker, {:pipeline_ready, media})
    assert_receive {:DOWN, ^ref, :process, ^media, :normal}, 2_000
    assert {:error, :stream_unavailable} = CameraStream.file(worker, "index.m3u8")
  end

  test "a disconnected pipeline becomes unavailable and reconnects with a clean generation" do
    assert {:error, :warming_up} = Monitoring.media_file("division-1", "secundaria", "index.m3u8")
    assert_receive {:media_started, media, options}
    File.write!(Path.join(options.directory, "old.m4s"), "old")
    ref = Process.monitor(media)
    GenServer.stop(media, :normal)
    assert_receive {:DOWN, ^ref, :process, ^media, :normal}
    assert_receive {:media_started, new_media, new_options}, 4_000
    assert new_media != media
    refute File.exists?(Path.join(options.directory, "old.m4s"))
    assert new_options.generation != options.generation
    assert {:error, :stream_unavailable} = CameraStream.file(options.owner, "index.m3u8")
  end
end

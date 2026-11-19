defmodule Sentinel.Detection.StreamIsolationTest do
  use Sentinel.DataCase, async: false
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  alias Sentinel.Monitoring

  setup do
    camera_source_fixture("division-1", "secundaria", "rtsp://example.test/private")
    previous = Monitoring.config()
    detection = Application.get_env(:sentinel, :detection, [])
    root = Path.join(System.tmp_dir!(), "detector-stream-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    for ext <- ~w(pt onnx), do: File.write!(Path.join(root, "yolo11n.#{ext}"), "fixture")

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    Application.put_env(:sentinel, :media_test_owner, self())
    Application.put_env(:sentinel, :detection, model_directory: root, python: __ENV__.file)

    Application.put_env(
      :sentinel,
      :monitoring,
      Keyword.merge(previous,
        hls_directory: root,
        pipeline_module: Sentinel.TestMediaPipeline
      )
    )

    on_exit(fn ->
      for key <- [
            {"division-1", "secundaria"},
            {"division-1", "secundaria", "python"},
            {"division-1", "secundaria", "elixir"}
          ],
          {pid, _} <- Registry.lookup(Sentinel.Monitoring.Registry, key),
          do: DynamicSupervisor.terminate_child(Sentinel.Monitoring.Supervisor, pid)

      Application.put_env(:sentinel, :monitoring, previous)
      Application.put_env(:sentinel, :detection, detection)
      Application.delete_env(:sentinel, :media_test_owner)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "engines use independent generations and two viewers share the same backend" do
    options =
      for engine <- ~w(off python elixir) do
        assert {:error, :warming_up} =
                 Monitoring.media_file("division-1", "secundaria", "index.m3u8", engine)

        assert_receive {:media_started, pipeline, options}
        assert options.engine == engine
        send(options.owner, {:detection_status, pipeline, :active})
        _ = :sys.get_state(options.owner)
        assert Monitoring.detection_status("division-1", "secundaria", engine) == :active

        assert {:error, :warming_up} =
                 Monitoring.media_file("division-1", "secundaria", "index.m3u8", engine)

        refute_received {:media_started, _, _}
        options
      end

    assert length(Enum.uniq_by(options, & &1.directory)) == 3
    assert length(Enum.uniq_by(options, & &1.generation)) == 3

    assert {:error, :unknown_engine} =
             Monitoring.media_file("division-1", "secundaria", "index.m3u8", "invalid")
  end
end

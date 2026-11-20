defmodule Sentinel.VisitorCounting.ManagerTest do
  use Sentinel.DataCase, async: false
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  alias Sentinel.{Monitoring, VisitorCounting}
  alias Sentinel.VisitorCounting.Manager

  setup do
    previous = Application.get_env(:sentinel, :visitor_counting, [])
    monitoring = Monitoring.config()
    camera_source_fixture("division-1", "secundaria", "rtsp://example.test/1")
    camera_source_fixture("division-2", "secundaria", "rtsp://example.test/2")

    Application.put_env(:sentinel, :visitor_counting,
      pipeline_module: Sentinel.TestMediaPipeline,
      start_manager: false,
      reconnect_ms: 5
    )

    Application.put_env(
      :sentinel,
      :monitoring,
      Keyword.merge(monitoring,
        pipeline_module: Sentinel.TestMediaPipeline
      )
    )

    Application.put_env(:sentinel, :media_test_owner, self())

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    on_exit(fn ->
      Application.put_env(:sentinel, :visitor_counting, previous)
      Application.put_env(:sentinel, :monitoring, monitoring)
      Application.delete_env(:sentinel, :media_test_owner)

      for {id, quality} <- [{"division-1", "secundaria"}] do
        for {pid, _} <- Registry.lookup(Sentinel.Monitoring.Registry, {id, quality}) do
          DynamicSupervisor.terminate_child(Sentinel.Monitoring.Supervisor, pid)
        end
      end
    end)

    :ok
  end

  test "starts without viewers, respects capacity, revisions and disable" do
    assert {:ok, _} = VisitorCounting.configure_rule("division-1", %{enabled: true})
    assert {:ok, _} = VisitorCounting.configure_rule("division-2", %{enabled: true})
    manager = start_supervised!({Manager, max_cameras: 1})
    :sys.get_state(manager)
    assert_receive {:media_started, pipeline, %{rule: %{camera_id: "division-1"}}}
    assert Manager.status("division-2") == :capacity
    assert length(Registry.lookup(Sentinel.VisitorCounting.Registry, "division-1")) == 1
    Manager.sync()
    refute_received {:media_started, _, _}
    ref = Process.monitor(pipeline)
    assert {:ok, _} = VisitorCounting.configure_rule("division-1", %{enabled: false})
    Manager.sync()
    assert_receive {:DOWN, ^ref, :process, ^pipeline, :normal}
    assert_receive {:media_started, _, %{rule: %{camera_id: "division-2"}}}
    assert Manager.status("division-1") == :disabled
  end

  test "reconnect creates new session and shutting camera stops pipeline" do
    VisitorCounting.configure_rule("division-1", %{enabled: true})
    manager = start_supervised!({Manager, []})
    :sys.get_state(manager)
    assert_receive {:media_started, first, options}
    GenServer.stop(first, :normal)
    assert_receive {:media_started, second, next}, 1_000
    refute first == second
    refute options.session == next.session
    send(next.owner, {:analytics_status, second, :active})
    assert Manager.status("division-1") == :active
    monitor = Process.monitor(second)
    stop_supervised!(Manager)
    assert_receive {:DOWN, ^monitor, :process, ^second, :normal}
  end

  test "counter re-resolves PostgreSQL source after reconnect and fails safely when absent" do
    VisitorCounting.configure_rule("division-1", %{enabled: true})
    manager = start_supervised!({Manager, []})
    :sys.get_state(manager)
    assert_receive {:media_started, first, options}
    assert options.source_url == "rtsp://example.test/1"
    query = from s in Sentinel.Monitoring.CameraSource, where: s.camera_id == "division-1"
    Repo.update_all(query, [set: [url: "rtsp://example.test/updated"]], log: false)
    GenServer.stop(first, :normal)
    assert_receive {:media_started, second, next}, 1_000
    assert next.source_url == "rtsp://example.test/updated"
    Repo.delete_all(query)
    GenServer.stop(second, :normal)
    [{camera, _}] = Registry.lookup(Sentinel.VisitorCounting.Registry, "division-1")
    _ = :sys.get_state(camera)
    assert Manager.status("division-1") == :error
    refute_received {:media_started, _, _}
  end

  test "source replacement and archive reconcile only the affected counter" do
    assert {:ok, _} = VisitorCounting.configure_rule("division-1", %{enabled: true})
    assert {:ok, _} = VisitorCounting.configure_rule("division-2", %{enabled: true})
    start_supervised!({Manager, max_cameras: 2})
    assert_receive {:media_started, first, %{rule: %{camera_id: "division-1"}}}
    assert_receive {:media_started, other, %{rule: %{camera_id: "division-2"}}}
    first_ref = Process.monitor(first)
    other_ref = Process.monitor(other)

    camera = %{id: "division-1", branch: "División", label: "Entrada", color: "rose"}
    assert {:ok, _} = Monitoring.save_camera(camera)
    assert Manager.sync() == :ok
    refute_received {:DOWN, ^first_ref, :process, ^first, _}

    assert {:ok, _} =
             Monitoring.save_camera(camera, %{"secundaria" => "rtsp://example.test/replacement"})

    assert_receive {:DOWN, ^first_ref, :process, ^first, :normal}

    assert_receive {:media_started, replacement,
                    %{
                      rule: %{camera_id: "division-1"},
                      source_url: "rtsp://example.test/replacement"
                    }}

    replacement_ref = Process.monitor(replacement)
    assert {:ok, _} = Monitoring.archive_camera("division-1")
    assert_receive {:DOWN, ^replacement_ref, :process, ^replacement, :normal}
    assert Manager.status("division-1") == :disabled
    assert {:ok, _} = Monitoring.restore_camera("division-1")
    assert Manager.sync() == :ok
    assert Manager.status("division-1") == :disabled
    refute_received {:media_started, _, %{rule: %{camera_id: "division-1"}}}
    refute_received {:DOWN, ^other_ref, :process, ^other, _}
  end

  test "a previous primary registration does not block a new secondary session" do
    config = Application.fetch_env!(:sentinel, :visitor_counting)

    Application.put_env(
      :sentinel,
      :visitor_counting,
      Keyword.merge(config,
        primary_snapshots: true,
        snapshot_pipeline_module: Sentinel.TestMediaPipeline
      )
    )

    camera_source_fixture("division-1", "principal", "rtsp://example.test/primary")
    registry = Sentinel.VisitorCounting.SnapshotRegistry
    {:ok, _} = Registry.register(registry, "division-1", :previous_source)

    {:ok, rule} = VisitorCounting.configure_rule("division-1", %{enabled: true})
    start_supervised!({Manager, []})
    assert_receive {:media_started, secondary, %{rule: %{camera_id: "division-1"}}}
    [{counter, _}] = Registry.lookup(Sentinel.VisitorCounting.Registry, rule.camera_id)
    _ = :sys.get_state(counter)
    Registry.unregister(registry, "division-1")
    assert_receive {:media_started, _, %{generation: _}}, 3_000
    assert :sys.get_state(counter).pipeline == secondary
  end

  test "opening HLS viewers cannot duplicate the canonical counter" do
    VisitorCounting.configure_rule("division-1", %{enabled: true})
    manager = start_supervised!({Manager, []})
    :sys.get_state(manager)
    assert_receive {:media_started, _, %{rule: _}}
    [{counter, _}] = Registry.lookup(Sentinel.VisitorCounting.Registry, "division-1")
    Monitoring.media_file("division-1", "secundaria", "index.m3u8")
    assert_receive {:media_started, _, %{engine: "off"}}
    Monitoring.media_file("division-1", "secundaria", "index.m3u8")
    Monitoring.player_url("division-1", "secundaria", "elixir")
    Manager.sync()
    assert [{^counter, _}] = Registry.lookup(Sentinel.VisitorCounting.Registry, "division-1")
    refute_received {:media_started, _, %{rule: _}}
  end
end

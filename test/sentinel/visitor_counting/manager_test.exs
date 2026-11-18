defmodule Sentinel.VisitorCounting.ManagerTest do
  use Sentinel.DataCase, async: false
  alias Sentinel.{Monitoring, VisitorCounting}
  alias Sentinel.VisitorCounting.Manager

  setup do
    previous = Application.get_env(:sentinel, :visitor_counting, [])
    monitoring = Monitoring.config()

    Application.put_env(:sentinel, :visitor_counting,
      pipeline_module: Sentinel.TestMediaPipeline,
      start_manager: false,
      reconnect_ms: 5
    )

    Application.put_env(
      :sentinel,
      :monitoring,
      Keyword.merge(monitoring,
        pipeline_module: Sentinel.TestMediaPipeline,
        sources: %{
          "division-1" => %{"secundaria" => "rtsp://example.test/1"},
          "division-2" => %{"secundaria" => "rtsp://example.test/2"}
        }
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

defmodule Sentinel.VisitorCounting.SnapshotSourceTest do
  use Sentinel.DataCase, async: false
  import Sentinel.MonitoringFixtures
  alias Sentinel.VisitorCounting.SnapshotSource

  setup do
    camera_catalog_fixture()
    camera_source_fixture("division-1", "principal", "rtsp://example.test/primary")
    Application.put_env(:sentinel, :media_test_owner, self())
    on_exit(fn -> Application.delete_env(:sentinel, :media_test_owner) end)

    start_supervised!(
      {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
    )

    owner = start_supervised!({Agent, fn -> nil end})

    source =
      start_supervised!(
        {SnapshotSource,
         camera_id: "division-1", owner: owner, runner: Sentinel.TestMediaPipeline}
      )

    assert_receive {:media_started, pipeline, options}
    %{source: source, owner: owner, pipeline: pipeline, options: options}
  end

  test "primary failure invalidates history, reconnects independently and owner death cleans up",
       ctx do
    gen = SnapshotSource.generation("division-1")
    assert :ok = SnapshotSource.put(ctx.source, gen, frame())
    assert {:ok, %{frames: [_]}} = SnapshotSource.read("division-1")
    GenServer.stop(ctx.pipeline, :normal)
    assert_receive {:media_started, next, options}, 2_000
    refute options.generation == ctx.options.generation
    assert {:ok, %{frames: []}} = SnapshotSource.read("division-1")
    assert {:error, :generation_mismatch} = SnapshotSource.put(ctx.source, gen, frame())
    source_ref = Process.monitor(ctx.source)
    pipeline_ref = Process.monitor(next)
    GenServer.stop(ctx.owner, :normal)
    assert_receive {:DOWN, ^source_ref, :process, _, :normal}
    assert_receive {:DOWN, ^pipeline_ref, :process, _, :normal}
    assert {:error, reason} = SnapshotSource.read("division-1")
    assert reason in [:missing, :unavailable]
  end

  test "cache count, bytes and dimensions are bounded; format change clears history", ctx do
    gen = SnapshotSource.generation("division-1")
    for _ <- 1..20, do: assert(:ok = SnapshotSource.put(ctx.source, gen, frame()))
    assert {:ok, %{frames: frames, bytes: bytes}} = SnapshotSource.read("division-1")
    assert length(frames) == 6
    assert bytes == 24
    assert {:ok, next_generation} = SnapshotSource.format(ctx.source, ctx.options.generation)
    refute next_generation == gen
    assert {:ok, %{frames: []}} = SnapshotSource.read("division-1")

    assert {:error, :oversized} =
             SnapshotSource.put(ctx.source, next_generation, %{frame() | width: 4000})
  end

  defp frame,
    do: %{
      jpeg: "jpeg",
      width: 1920,
      height: 1080,
      received_mono: System.monotonic_time(:millisecond),
      received_at: DateTime.utc_now()
    }
end

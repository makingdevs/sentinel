defmodule Sentinel.VisitorCounting.SnapshotSelectorTest do
  use ExUnit.Case, async: true
  alias Sentinel.VisitorCounting.SnapshotSelector

  test "selects only same-camera, same-generation, nonfuture receipts within 750ms" do
    now = System.monotonic_time(:millisecond)
    generation = make_ref()
    frame = %{captured_at: now, snapshot_generation: generation}
    image = %{camera_id: "a", received_mono: now - 500, jpeg: "immutable"}
    cache = %{generation: generation, frames: [image], reason: nil}
    assert {:ok, ^image} = SnapshotSelector.select("a", frame, {:ok, cache})
    assert {:error, "future"} = SnapshotSelector.select("b", frame, {:ok, cache})

    assert {:error, "generation_mismatch"} =
             SnapshotSelector.select(
               "a",
               %{frame | snapshot_generation: make_ref()},
               {:ok, cache}
             )

    assert {:error, "stale"} =
             SnapshotSelector.select(
               "a",
               frame,
               {:ok, %{cache | frames: [%{image | received_mono: now - 751}]}}
             )

    assert {:error, "future"} =
             SnapshotSelector.select(
               "a",
               frame,
               {:ok, %{cache | frames: [%{image | received_mono: now + 1}]}}
             )

    assert {:ok, _} =
             SnapshotSelector.select(
               "a",
               frame,
               {:ok, %{cache | frames: [%{image | received_mono: now - 750}]}}
             )

    assert {:error, "stale"} =
             SnapshotSelector.select(
               "a",
               %{frame | captured_at: now - 4000},
               {:ok, %{cache | frames: [%{image | received_mono: now - 4100}]}}
             )
  end
end

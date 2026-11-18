defmodule Sentinel.VisitorCounting.WriterTest do
  use Sentinel.DataCase, async: false
  alias Sentinel.VisitorCounting.{Snapshots, Writer}

  setup do
    previous = Application.get_env(:sentinel, :visitor_counting, [])
    root = "/private/tmp/visitor-writer-#{System.unique_integer([:positive])}"
    Application.put_env(:sentinel, :visitor_counting, snapshot_root: root, start_manager: false)
    Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_events")

    on_exit(fn ->
      Application.put_env(:sentinel, :visitor_counting, previous)
      File.rm_rf!(root)
    end)

    :ok
  end

  test "admission is bounded before mailbox delivery and publication follows persistence" do
    capacity = Writer.stats("division-1").capacity
    :sys.suspend(Writer)

    try do
      for i <- 1..capacity, do: assert(:ok == Writer.enqueue(event("bounded-#{i}")))
      assert {:error, :saturated} = Writer.enqueue(event("overflow"))
      assert Writer.stats("division-1").queued == capacity
      refute_received {:passage_saved, _}
    after
      :sys.resume(Writer)
    end

    for _ <- 1..capacity do
      assert_receive {:passage_saved, id}, 5_000
      saved = Sentinel.VisitorCounting.get_event(id)
      assert {:ok, path} = Snapshots.path(saved.snapshot_key)
      assert {:ok, image} = Image.open(path)
      assert Image.width(image) == 160
    end

    :sys.get_state(Writer)
    assert Writer.stats("division-1").queued == 0
    assert Writer.stats("division-1").dropped >= 1
    assert :ok = Writer.enqueue(event("bounded-1"))
    :sys.get_state(Writer)
    refute_receive {:passage_saved, _}
  end

  test "three failed attempts release slot, record loss and never publish" do
    before = Writer.stats("division-1")
    ref = make_ref()
    owner = self()

    :telemetry.attach(
      ref,
      [:sentinel, :visitor_counting, :write],
      fn _, measure, _, _ ->
        send(owner, {:write_measure, measure})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(ref) end)
    event = event("failed")
    assert :ok = Writer.enqueue(%{event | attrs: %{event.attrs | direction: "invalid"}})
    for _ <- 1..3, do: assert_receive({:write_measure, %{failures: 1}}, 5_000)
    assert_receive {:write_measure, %{dropped: 1}}
    :sys.get_state(Writer)
    after_stats = Writer.stats("division-1")
    assert after_stats.failures == before.failures + 3
    assert after_stats.dropped == before.dropped + 1
    assert after_stats.queued == 0
    refute_received {:passage_saved, _}
  end

  defp event(key) do
    %{
      attrs: %{
        camera_id: "division-1",
        rule_revision: 1,
        crossed_at: DateTime.utc_now(),
        direction: "entry",
        tracking_session_id: "session",
        track_id: 1,
        crossing_number: 1,
        confidence: 0.9,
        bbox: %{cx: 0.5, cy: 0.5, w: 0.2, h: 0.4},
        dedupe_key: key
      },
      frame: %{width: 160, height: 100, payload: :binary.copy(<<0>>, 160 * 100 * 3)},
      object: %{class_idx: 0, prob: 0.9, bbox: %{cx: 80, cy: 50, w: 32, h: 40}}
    }
  end
end

defmodule Sentinel.Detection.WorkerTest do
  use ExUnit.Case, async: true
  alias Sentinel.Detection.Worker

  test "persistent worker reports correlated results and stops after a backend failure" do
    worker =
      start_supervised!(
        {Worker, owner: self(), engine: "python", adapter: Sentinel.TestDetectionAdapter}
      )

    assert_receive {:detector_ready, ^worker}
    frame = %{frame_id: 3, pts: 100, captured_at: 20, payload: "rgb"}
    send(worker, {:infer, frame})
    assert_receive {:detector_result, ^worker, 3, 100, 20, {:ok, [_]}, _duration}
    ref = Process.monitor(worker)
    send(worker, {:infer, %{frame | frame_id: 4, payload: "failure"}})
    assert_receive {:detector_result, ^worker, 4, 100, 20, {:error, :fixture_failure}, _}
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
  end

  test "owner exit releases its supervised detector" do
    owner =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :stop -> :ok
           end
         end}
      )

    worker =
      start_supervised!(
        {Worker, owner: owner, engine: "elixir", adapter: Sentinel.TestDetectionAdapter}
      )

    _ = :sys.get_state(worker)
    ref = Process.monitor(worker)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
  end
end

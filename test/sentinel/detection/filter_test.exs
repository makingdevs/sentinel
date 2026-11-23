defmodule Sentinel.Detection.FilterTest do
  use ExUnit.Case, async: true
  alias Sentinel.Detection.Filter

  test "keeps one request in flight and replaces a single pending frame" do
    {[], state} = Filter.handle_init(%{}, %Filter{engine: "python", generation: "one"})

    format = %Membrane.RawVideo{
      width: 2,
      height: 2,
      framerate: {25, 1},
      pixel_format: :RGB,
      aligned: true
    }

    {_, state} = Filter.handle_stream_format(:input, format, %{}, state)
    state = %{state | ready?: true, worker: self()}
    buffer = %Membrane.Buffer{payload: :binary.copy(<<0>>, 12), pts: 0}
    {_, state} = Filter.handle_buffer(:input, buffer, %{}, state)
    assert_receive {:infer, %{frame_id: 1}}
    assert state.busy == 1
    {_, state} = Filter.handle_buffer(:input, buffer, %{}, state)
    {_, state} = Filter.handle_buffer(:input, buffer, %{}, state)
    assert state.pending.frame_id == 3
    refute_receive {:infer, _}
    Process.cancel_timer(state.timer)
    assert {[], ^state} = Filter.handle_info({:inference_timeout, 999}, %{}, state)
  end

  test "expired boxes are removed and old worker results ignored" do
    {[], state} = Filter.handle_init(%{}, %Filter{engine: "elixir", generation: "two"})

    format = %Membrane.RawVideo{
      width: 2,
      height: 2,
      framerate: {25, 1},
      pixel_format: :RGB,
      aligned: true
    }

    {_, state} = Filter.handle_stream_format(:input, format, %{}, state)
    now = System.monotonic_time(:millisecond)
    state = %{state | objects: [%{class_idx: 0}], result_at: now - 1000, result_pts: 0}
    buffer = %Membrane.Buffer{payload: :binary.copy(<<0>>, 12), pts: Membrane.Time.seconds(1)}
    {[buffer: {:output, output}], state} = Filter.handle_buffer(:input, buffer, %{}, state)
    assert output.metadata.detected_objects == []

    assert {[], ^state} =
             Filter.handle_info({:detector_result, self(), 99, 0, now, {:ok, []}, 1}, %{}, state)
  end

  test "a resolution change clears boxes and pending frames" do
    {[], state} = Filter.handle_init(%{}, %Filter{engine: "python", generation: "three"})

    format = %Membrane.RawVideo{
      width: 4,
      height: 2,
      framerate: {25, 1},
      pixel_format: :RGB,
      aligned: true
    }

    state = %{state | objects: [%{class_idx: 0}], result_at: 1, pending: %{frame_id: 9}}
    {_, state} = Filter.handle_stream_format(:input, format, %{}, state)
    assert state.objects == []
    assert state.pending == nil
    assert state.result_at == nil
  end

  test "completion submits only the newest pending frame when the interval is due" do
    state = ready_state()
    buffer = %Membrane.Buffer{payload: <<1>>, pts: 0}
    {_, state} = Filter.handle_buffer(:input, buffer, %{}, state)
    assert_receive {:infer, %{frame_id: 1}}
    {_, state} = Filter.handle_buffer(:input, %{buffer | payload: <<2>>}, %{}, state)
    {_, state} = Filter.handle_buffer(:input, %{buffer | payload: <<3>>}, %{}, state)
    state = %{state | last_started: System.monotonic_time(:millisecond) - 10_000}

    {[], state} =
      Filter.handle_info(
        {:detector_result, self(), 1, 0, System.monotonic_time(:millisecond), {:ok, []}, 1},
        %{},
        state
      )

    assert_receive {:infer, %{frame_id: 3, payload: <<3>>}}
    refute_receive {:infer, _}
    assert state.pending == nil
    Process.cancel_timer(state.timer)
  end

  test "completion discards pending frames while the sampling interval is not due" do
    state = %{
      ready_state()
      | last_started: System.monotonic_time(:millisecond) + 10_000,
        busy: 1,
        timer: Process.send_after(self(), :unused, 60_000),
        pending: %{frame_id: 2},
        inflight_format: {2, 2}
    }

    {[], state} =
      Filter.handle_info(
        {:detector_result, self(), 1, 0, System.monotonic_time(:millisecond), {:ok, []}, 1},
        %{},
        state
      )

    assert state.pending == nil
    assert state.busy == nil
    refute_receive {:infer, _}
  end

  test "fresh boxes require valid forward PTS within the media age window" do
    now = System.monotonic_time(:millisecond)

    state = %{
      ready_state()
      | ready?: false,
        objects: [%{class_idx: 0}],
        result_at: now,
        result_pts: Membrane.Time.seconds(1)
    }

    for pts <- [nil, Membrane.Time.seconds(1) - 1, Membrane.Time.seconds(2)] do
      {[buffer: {:output, output}], _} =
        Filter.handle_buffer(:input, %Membrane.Buffer{payload: <<>>, pts: pts}, %{}, state)

      assert output.metadata.detected_objects == []
    end

    {[buffer: {:output, output}], _} =
      Filter.handle_buffer(
        :input,
        %Membrane.Buffer{payload: <<>>, pts: Membrane.Time.seconds(1)},
        %{},
        state
      )

    assert output.metadata.detected_objects == state.objects
  end

  test "a result submitted before a format change does not restore old boxes" do
    state = %{
      ready_state()
      | busy: 1,
        inflight_format: {4, 2},
        timer: Process.send_after(self(), :unused, 60_000)
    }

    objects = [%{"class_id" => 0, "confidence" => 0.9, "xyxy" => [0, 0, 2, 2]}]

    {[], state} =
      Filter.handle_info(
        {:detector_result, self(), 1, 0, System.monotonic_time(:millisecond), {:ok, objects}, 1},
        %{},
        state
      )

    assert state.objects == []
    assert state.busy == nil
  end

  test "oversized formats retain the existing validation error" do
    assert_raise ArgumentError, "detection frame exceeds 1280px bound", fn ->
      Filter.handle_stream_format(:input, %{width: 1281, height: 2}, %{}, ready_state())
    end
  end

  test "frame telemetry counts replacement drops and status changes recover with fresh boxes" do
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:sentinel, :detection, :frame],
        fn _, measurements, metadata, _ ->
          send(owner, {:frame_metric, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    now = System.monotonic_time(:millisecond)

    state = %{
      ready_state()
      | busy: 1,
        pending: %{frame_id: 2},
        last_started: now - 10_000,
        objects: [%{class_idx: 0}],
        result_at: now - 10_000,
        result_pts: 0
    }

    buffer = %Membrane.Buffer{payload: <<>>, pts: 0}

    {[notify_parent: {:detection_status, :saturated}, buffer: {:output, output}], state} =
      Filter.handle_buffer(:input, buffer, %{}, state)

    assert output.metadata.detected_objects == []

    assert_receive {:frame_metric, %{frames: 1, dropped: 1, boxed: 0, box_age_ms: 0},
                    %{engine: "python", generation: "regression"}}

    state = %{state | result_at: System.monotonic_time(:millisecond)}

    {[notify_parent: {:detection_status, :active}, buffer: {:output, output}], _} =
      Filter.handle_buffer(:input, buffer, %{}, state)

    assert output.metadata.detected_objects == state.objects
    assert_receive {:frame_metric, %{dropped: 1, boxed: 1}, _}
  end

  test "worker loss clears queued work and retries stop at the existing limit" do
    ref = make_ref()

    state = %{
      ready_state()
      | monitor: ref,
        busy: 1,
        pending: %{frame_id: 2},
        objects: [%{class_idx: 0}],
        retry_count: 3
    }

    {[notify_parent: {:detection_status, :error}], state} =
      Filter.handle_info({:DOWN, ref, :process, self(), :normal}, %{}, state)

    assert state.worker == nil
    assert state.busy == nil
    assert state.pending == nil
    assert state.objects == []
    assert state.retry_count == 3
    assert {[], ^state} = Filter.handle_info({:retry_detector, "old-generation"}, %{}, state)
  end

  defp ready_state do
    {[], state} = Filter.handle_init(%{}, %Filter{engine: "python", generation: "regression"})

    {_, state} =
      Filter.handle_stream_format(
        :input,
        %Membrane.RawVideo{
          width: 2,
          height: 2,
          framerate: {25, 1},
          pixel_format: :RGB,
          aligned: true
        },
        %{},
        state
      )

    %{state | ready?: true, worker: self()}
  end
end

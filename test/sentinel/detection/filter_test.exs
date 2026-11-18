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
end

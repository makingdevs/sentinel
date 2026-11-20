defmodule Sentinel.VisitorCounting.SnapshotSamplerTest do
  use ExUnit.Case, async: true
  alias Sentinel.VisitorCounting.SnapshotSampler

  test "sampling drops without downstream demand and before converting or retaining frames" do
    {[], state} = SnapshotSampler.handle_init(%{}, %{})

    format = %Membrane.RawVideo{
      width: 1920,
      height: 1080,
      pixel_format: :I420,
      framerate: {25, 1},
      aligned: true
    }

    {[stream_format: {:output, ^format}], state} =
      SnapshotSampler.handle_stream_format(:input, format, %{}, state)

    buffer = %Membrane.Buffer{payload: "raw"}

    assert {[], ^state} =
             SnapshotSampler.handle_buffer(
               :input,
               buffer,
               %{pads: %{output: %{demand: 0}}},
               state
             )

    {[buffer: {:output, sampled}], state} =
      SnapshotSampler.handle_buffer(:input, buffer, %{pads: %{output: %{demand: 1}}}, state)

    assert sampled.metadata.snapshot_received_mono < state.next_at
    assert sampled.payload == buffer.payload

    assert {[], ^state} =
             SnapshotSampler.handle_buffer(
               :input,
               buffer,
               %{pads: %{output: %{demand: 1}}},
               state
             )

    refute Map.has_key?(state, :pending)

    assert {[notify_parent: {:snapshot_error, :oversized}], _} =
             SnapshotSampler.handle_stream_format(:input, %{format | width: 4000}, %{}, state)
  end
end

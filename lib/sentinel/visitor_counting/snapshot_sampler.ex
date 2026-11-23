defmodule Sentinel.VisitorCounting.SnapshotSampler do
  @moduledoc "Drop decoded frames before RGB conversion. No raw history or unbounded demand."
  use Membrane.Filter, flow_control_hints?: false
  def_input_pad(:input, accepted_format: %Membrane.RawVideo{}, flow_control: :auto)

  def_output_pad(:output,
    accepted_format: %Membrane.RawVideo{},
    flow_control: :manual,
    demand_unit: :buffers
  )

  @impl true
  def handle_init(_, _), do: {[], %{next_at: nil, valid?: false}}

  @impl true
  def handle_stream_format(:input, format, _, state) do
    valid? = format.width in 1..3840 and format.height in 1..2160

    cond do
      valid? -> {[stream_format: {:output, format}], %{state | next_at: nil, valid?: true}}
      true -> {[notify_parent: {:snapshot_error, :oversized}], %{state | valid?: false}}
    end
  end

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    now = System.monotonic_time(:millisecond)

    cond do
      state.valid? and ctx.pads.output.demand > 0 and
          (state.next_at == nil or now >= state.next_at) ->
        metadata =
          Map.merge(buffer.metadata, %{
            snapshot_received_mono: now,
            snapshot_received_at: DateTime.utc_now()
          })

        {[buffer: {:output, %{buffer | metadata: metadata}}], %{state | next_at: now + 500}}

      true ->
        {[], state}
    end
  end

  @impl true
  def handle_demand(:output, _, :buffers, _, state), do: {[], state}
  @impl true
  def handle_end_of_stream(:input, _, state), do: {[end_of_stream: :output], state}
end

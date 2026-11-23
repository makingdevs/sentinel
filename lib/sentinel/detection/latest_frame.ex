defmodule Sentinel.Detection.LatestFrame do
  @moduledoc "Bridges live push input to pull output with exactly one replaceable raw frame."
  use Membrane.Filter, flow_control_hints?: false

  def_input_pad(:input,
    accepted_format: %Membrane.RawVideo{pixel_format: :RGB},
    flow_control: :auto
  )

  def_output_pad(:output,
    accepted_format: %Membrane.RawVideo{pixel_format: :RGB},
    flow_control: :manual,
    demand_unit: :buffers
  )

  def_options(engine: [spec: String.t()], generation: [spec: String.t()])

  @impl true
  def handle_init(_ctx, opts),
    do: {[], %{pending: nil, engine: opts.engine, generation: opts.generation}}

  @impl true
  def handle_stream_format(:input, format, _ctx, state),
    do: {[stream_format: {:output, format}], %{state | pending: nil}}

  @impl true
  def handle_buffer(:input, buffer, ctx, state) do
    case state.pending do
      nil ->
        nil

      _ ->
        :telemetry.execute([:sentinel, :detection, :video_drop], %{frames: 1}, %{
          engine: state.engine,
          generation: state.generation
        })
    end

    cond do
      ctx.pads.output.demand > 0 -> {[buffer: {:output, buffer}], %{state | pending: nil}}
      true -> {[], %{state | pending: buffer}}
    end
  end

  @impl true
  def handle_demand(:output, _size, :buffers, _ctx, %{pending: nil} = state), do: {[], state}

  def handle_demand(:output, _size, :buffers, _ctx, state),
    do: {[buffer: {:output, state.pending}], %{state | pending: nil}}

  @impl true
  def handle_end_of_stream(:input, _ctx, state),
    do: {[end_of_stream: :output], %{state | pending: nil}}
end

defmodule Sentinel.VisitorCounting.SnapshotSink do
  @moduledoc "One native JPEG encoding operation at a time, with explicit buffer demand."
  use Membrane.Sink
  alias Sentinel.VisitorCounting.SnapshotSource

  def_input_pad(:input,
    accepted_format: %Membrane.RawVideo{pixel_format: :RGB},
    flow_control: :manual,
    demand_unit: :buffers
  )

  def_options(source: [spec: pid()], generation: [spec: reference()])
  @impl true
  def handle_init(_, opts),
    do:
      {[],
       %{
         source: opts.source,
         generation: opts.generation,
         connection: opts.generation,
         format: nil
       }}

  @impl true
  def handle_playing(_, state), do: {[demand: {:input, 1}], state}
  @impl true
  def handle_stream_format(:input, format, _, state) do
    {:ok, generation} = SnapshotSource.format(state.source, state.connection)
    {[], %{state | format: format, generation: generation}}
  end

  @impl true
  def handle_buffer(:input, buffer, _, state) do
    with {:ok, image} <- Membrane.RawVideo.payload_to_image(buffer.payload, state.format),
         {:ok, jpeg} <- Image.write(image, :memory, suffix: ".jpg", quality: 85) do
      SnapshotSource.put(state.source, state.generation, %{
        jpeg: jpeg,
        width: state.format.width,
        height: state.format.height,
        received_mono: buffer.metadata.snapshot_received_mono,
        received_at: buffer.metadata.snapshot_received_at
      })
    end

    {[demand: {:input, 1}], state}
  end
end

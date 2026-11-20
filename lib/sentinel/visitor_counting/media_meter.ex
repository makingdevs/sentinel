defmodule Sentinel.VisitorCounting.MediaMeter do
  @moduledoc "Encoded media ingress telemetry. Counts payload bytes, excluding RTSP/TCP overhead."
  use Membrane.Filter
  def_input_pad(:input, accepted_format: _any)
  def_output_pad(:output, accepted_format: _any)
  def_options(camera_id: [spec: String.t()], channel: [spec: :primary | :secondary])
  @impl true
  def handle_init(_, opts), do: {[], %{camera_id: opts.camera_id, channel: opts.channel}}
  @impl true
  def handle_buffer(:input, buffer, _, state) do
    :telemetry.execute(
      [:sentinel, :visitor_counting, :ingress],
      %{bytes: byte_size(buffer.payload)},
      state
    )

    {[buffer: {:output, buffer}], state}
  end
end

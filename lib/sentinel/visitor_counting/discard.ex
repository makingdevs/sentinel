defmodule Sentinel.VisitorCounting.Discard do
  @moduledoc false
  use Membrane.Sink
  def_input_pad(:input, accepted_format: %Membrane.RawVideo{pixel_format: :RGB})
  @impl true
  def handle_buffer(:input, _buffer, _ctx, state), do: {[], state}
end

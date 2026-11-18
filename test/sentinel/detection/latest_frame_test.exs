defmodule Sentinel.Detection.LatestFrameTest do
  use ExUnit.Case, async: true
  alias Sentinel.Detection.LatestFrame

  test "retains only the newest frame until downstream demand arrives" do
    {[], state} = LatestFrame.handle_init(%{}, %LatestFrame{engine: "python", generation: "test"})
    ctx = %{pads: %{output: %{demand: 0}}}

    state =
      Enum.reduce(1..100, state, fn pts, state ->
        assert {[], state} =
                 LatestFrame.handle_buffer(
                   :input,
                   %Membrane.Buffer{payload: <<pts>>, pts: pts},
                   ctx,
                   state
                 )

        state
      end)

    assert state.pending.pts == 100

    {[buffer: {:output, buffer}], state} =
      LatestFrame.handle_demand(:output, 1, :buffers, ctx, state)

    assert buffer.pts == 100
    assert state.pending == nil
    assert {[], ^state} = LatestFrame.handle_demand(:output, 1, :buffers, ctx, state)
  end
end

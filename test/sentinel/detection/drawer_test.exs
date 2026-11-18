defmodule Sentinel.Detection.DrawerTest do
  use ExUnit.Case, async: true
  alias Sentinel.Detection.Drawer

  test "cached overlay preserves new frame pixels and is invalidated when empty" do
    format = %Membrane.RawVideo{
      width: 100,
      height: 100,
      framerate: {25, 1},
      pixel_format: :RGB,
      aligned: true
    }

    {_, state} = Drawer.handle_stream_format(:input, format, %{}, %{})
    object = %{class_idx: 0, class: "Persona", prob: 0.9, bbox: %{cx: 50, cy: 60, w: 30, h: 30}}
    red = :binary.copy(<<255, 0, 0>>, 10_000)
    blue = :binary.copy(<<0, 0, 255>>, 10_000)
    {first, state} = Drawer.render(red, [object], state)
    overlay = state.overlay
    {second, state} = Drawer.render(blue, [object], state)
    assert state.overlay == overlay
    assert byte_size(first) == byte_size(red)
    assert binary_part(first, 0, 3) == <<255, 0, 0>>
    assert binary_part(second, 0, 3) == <<0, 0, 255>>
    refute first == red
    {^blue, state} = Drawer.render(blue, [], state)
    assert state.overlay == nil
  end
end

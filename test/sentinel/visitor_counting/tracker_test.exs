defmodule Sentinel.VisitorCounting.TrackerTest do
  use ExUnit.Case, async: true
  alias Sentinel.VisitorCounting.{Encoder, Processor, Rule, Tracker}

  test "two people keep separate tracks, count once, ignore cars and weak detections" do
    scene =
      for y <- [0.3, 0.35, 0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.65] do
        [
          person(0.3, y),
          person(0.7, y),
          %{person(0.5, y) | class_idx: 2},
          %{person(0.8, y) | prob: 0.4}
        ]
      end

    {tracker, events} = run(scene)
    assert map_size(tracker.tracks) == 2
    assert length(events) == 2
    assert Enum.uniq(Enum.map(events, & &1.attrs.direction)) == ["entry"]
    assert length(Enum.uniq(Enum.map(events, & &1.attrs.track_id))) == 2
  end

  test "line jitter does not repeatedly count; moving away rearms return and reentry" do
    ys =
      [0.3, 0.35, 0.4, 0.45, 0.55] ++
        List.duplicate(0.51, 10) ++
        [0.49, 0.51, 0.49, 0.6, 0.65, 0.6, 0.55, 0.45, 0.4, 0.35, 0.4, 0.45, 0.55]

    {_, events} = run(Enum.map(ys, &[person(0.5, &1)]))
    assert Enum.map(events, & &1.attrs.direction) == ["entry", "exit", "entry"]
    assert Enum.map(events, & &1.attrs.crossing_number) == [1, 2, 3]
    assert length(Enum.uniq(Enum.map(events, & &1.attrs.dedupe_key))) == 3
    assert length(Enum.uniq(Enum.map(events, & &1.attrs.track_id))) == 1
  end

  test "temporary absence preserves ID but resets consecutive confirmation; lost tracks expire" do
    rule = %Rule{max_missed: 2}
    {s, [id]} = Tracker.update(Tracker.new(), [person(0.5, 0.3)], {1000, 1000}, rule)
    {s, []} = Tracker.update(s, [], {1000, 1000}, rule)
    {s, [^id]} = Tracker.update(s, [person(0.5, 0.32)], {1000, 1000}, rule)
    assert s.tracks[id].hits == 1
    s = Enum.reduce(1..3, s, fn _, s -> elem(Tracker.update(s, [], {1000, 1000}, rule), 0) end)
    assert s.tracks == %{}
    {_, [new_id]} = Tracker.update(s, [person(0.5, 0.32)], {1000, 1000}, rule)
    refute new_id == id
  end

  test "crossing outside segment and unconfirmed detections do not count" do
    {_, events} = run(for y <- [0.3, 0.35, 0.4, 0.45, 0.55, 0.6], do: [person(0.02, y)])
    assert events == []
    {_, events} = run([[person(0.5, 0.45)], [person(0.5, 0.55)]])
    assert events == []
  end

  test "orientation reverses entry and session restart changes dedupe key" do
    scene = for y <- [0.3, 0.35, 0.4, 0.45, 0.55], do: [person(0.5, y)]
    {_, [a]} = run(scene)
    {_, [b]} = run(scene, %Rule{camera_id: "division-1", entry_direction: "negative"}, "new")
    assert a.attrs.direction == "entry"
    assert b.attrs.direction == "exit"
    refute a.attrs.dedupe_key == b.attrs.dedupe_key
  end

  test "bounded tracks and person detections" do
    objects = for i <- 1..300, do: person(i / 300, 0.3)
    {state, ids} = Tracker.update(Tracker.new(), objects, {1000, 1000}, %Rule{})
    assert map_size(state.tracks) == 100
    assert length(ids) == 100
  end

  test "annotated capture encodes as readable JPEG" do
    frame = %{width: 160, height: 100, payload: :binary.copy(<<0>>, 160 * 100 * 3)}
    object = %{class_idx: 0, prob: 0.9, bbox: %{cx: 80, cy: 50, w: 40, h: 60}}
    assert {:ok, jpeg} = Encoder.encode(%{frame: frame, object: object})
    assert {:ok, image} = Image.from_binary(jpeg)
    assert Image.width(image) == 160
    assert Image.height(image) == 100
  end

  defp run(scene, rule \\ %Rule{camera_id: "division-1"}, session \\ "session") do
    frame = %{width: 1000, height: 1000, payload: <<>>, crossed_at: DateTime.utc_now()}

    Enum.reduce(scene, {Tracker.new(), []}, fn objects, {state, events} ->
      {state, batch} = Processor.process(state, objects, frame, rule, session)
      {state, events ++ Enum.reverse(batch)}
    end)
  end

  defp person(x, foot),
    do: %{class_idx: 0, prob: 0.9, bbox: %{cx: x * 1000, cy: (foot - 0.1) * 1000, w: 100, h: 200}}
end

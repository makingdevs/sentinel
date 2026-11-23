defmodule Sentinel.VisitorCounting.Crossing do
  @moduledoc "Footpoint crossings of a finite directed segment, with hysteresis and rearming."

  def step(track, rule) do
    distance = distance(track.point, rule)

    side =
      cond do
        distance > rule.hysteresis -> 1
        distance < -rule.hysteresis -> -1
        true -> 0
      end

    state = track.crossing || %{side: nil, point: track.point, armed?: false, number: 0}
    far? = abs(distance) >= rule.hysteresis * 2
    confirmed? = track.hits >= rule.min_hits

    {state, event} =
      cond do
        not confirmed? or side == 0 ->
          {state, nil}

        state.side == nil ->
          {%{state | side: side, point: track.point, armed?: far?}, nil}

        state.side == side ->
          {%{state | point: track.point, armed?: state.armed? or far?}, nil}

        true ->
          {number, event} =
            crossing_event(
              state.armed? and intersects?(state.point, track.point, rule),
              state.number,
              side,
              rule
            )

          {%{state | side: side, point: track.point, armed?: false, number: number}, event}
      end

    {%{track | crossing: state}, event}
  end

  defp crossing_event(false, number, _side, _rule), do: {number, nil}

  defp crossing_event(true, number, side, rule),
    do: {number + 1, %{direction: direction(side, rule), crossing_number: number + 1}}

  defp direction(1, %{entry_direction: "positive"}), do: "entry"
  defp direction(1, _rule), do: "exit"
  defp direction(_side, %{entry_direction: "positive"}), do: "exit"
  defp direction(_side, _rule), do: "entry"

  defp distance({x, y}, r) do
    dx = r.x2 - r.x1
    dy = r.y2 - r.y1
    (dx * (y - r.y1) - dy * (x - r.x1)) / :math.sqrt(dx * dx + dy * dy)
  end

  defp intersects?({ax, ay} = a, {bx, by} = b, r) do
    da = distance(a, r)
    db = distance(b, r)
    t = da / (da - db)
    x = ax + (bx - ax) * t
    y = ay + (by - ay) * t
    dx = r.x2 - r.x1
    dy = r.y2 - r.y1
    projection = ((x - r.x1) * dx + (y - r.y1) * dy) / (dx * dx + dy * dy)
    projection >= 0 and projection <= 1
  end
end

defmodule Sentinel.VisitorCounting.Tracker do
  @moduledoc "Bounded greedy geometry/motion association. IDs are session-local, not identities."
  defstruct tracks: %{}, next_id: 1, max_tracks: 100

  def new, do: %__MODULE__{}

  def update(state, objects, {width, height}, rule) do
    detections =
      objects
      |> Enum.take(100)
      |> Enum.filter(&(&1.class_idx == 0 and &1.prob >= rule.confidence))
      |> Enum.map(fn object ->
        b = object.bbox

        %{
          bbox: %{cx: b.cx / width, cy: b.cy / height, w: b.w / width, h: b.h / height},
          confidence: object.prob,
          object: object
        }
      end)
      |> Enum.with_index()

    matches = associate(state.tracks, detections)
    tracks = age_tracks(state.tracks, rule.max_missed)

    {tracks, next_id, observed} =
      Enum.reduce(detections, {tracks, state.next_id, []}, fn {detection, index}, acc ->
        id = Map.get(matches, index, elem(acc, 1))
        observe(Map.get(state.tracks, id), detection, id, state.max_tracks, acc)
      end)

    {%{state | tracks: tracks, next_id: next_id}, Enum.reverse(observed)}
  end

  defp associate(tracks, detections) do
    candidates =
      for {id, track} <- tracks,
          {detection, index} <- detections,
          cost = cost(track, detection),
          cost < 1.0,
          do: {cost, id, index}

    {matches, _, _} =
      candidates
      |> Enum.sort()
      |> Enum.reduce({%{}, MapSet.new(), MapSet.new()}, &match_candidate/2)

    matches
  end

  defp match_candidate({_cost, id, index}, {matches, ids, indices} = acc) do
    cond do
      MapSet.member?(ids, id) or MapSet.member?(indices, index) -> acc
      true -> {Map.put(matches, index, id), MapSet.put(ids, id), MapSet.put(indices, index)}
    end
  end

  defp age_tracks(tracks, max_missed) do
    for {id, track} <- tracks,
        track.missed < max_missed,
        into: %{},
        do: {id, %{track | missed: track.missed + 1, hits: 0}}
  end

  defp observe(nil, _detection, _id, limit, {tracks, _next_id, _observed} = acc)
       when map_size(tracks) >= limit, do: acc

  defp observe(previous, detection, id, _limit, {tracks, next_id, observed}) do
    point = {detection.bbox.cx, detection.bbox.cy + detection.bbox.h / 2}
    {velocity, hits, crossing} = track_history(previous, point)

    track = %{
      id: id,
      bbox: detection.bbox,
      point: point,
      velocity: velocity,
      confidence: detection.confidence,
      object: detection.object,
      missed: 0,
      hits: hits,
      crossing: crossing
    }

    {Map.put(tracks, id, track), max(next_id, id + 1), [id | observed]}
  end

  defp track_history(nil, _point), do: {{0, 0}, 1, nil}

  defp track_history(previous, point),
    do: {delta(point, previous.point), previous.hits + 1, previous.crossing}

  defp delta({x, y}, {px, py}), do: {x - px, y - py}

  defp cost(track, detection) do
    {vx, vy} = track.velocity
    predicted = %{track.bbox | cx: track.bbox.cx + vx, cy: track.bbox.cy + vy}
    b = detection.bbox
    distance = :math.sqrt((predicted.cx - b.cx) ** 2 + (predicted.cy - b.cy) ** 2)
    overlap = iou(predicted, b)

    cond do
      distance <= 0.15 or overlap >= 0.1 -> distance * 3 + (1 - overlap) * 0.4
      true -> 2.0
    end
  end

  defp iou(a, b) do
    width = max(0, min(a.cx + a.w / 2, b.cx + b.w / 2) - max(a.cx - a.w / 2, b.cx - b.w / 2))
    height = max(0, min(a.cy + a.h / 2, b.cy + b.h / 2) - max(a.cy - a.h / 2, b.cy - b.h / 2))
    intersection = width * height
    intersection / max(0.000001, a.w * a.h + b.w * b.h - intersection)
  end
end

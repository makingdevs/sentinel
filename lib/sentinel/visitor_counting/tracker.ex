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

    candidates =
      for {id, track} <- state.tracks,
          {detection, index} <- detections,
          cost = cost(track, detection),
          cost < 1.0,
          do: {cost, id, index}

    {matches, _, _} =
      candidates
      |> Enum.sort()
      |> Enum.reduce(
        {%{}, MapSet.new(), MapSet.new()},
        fn {_cost, id, index}, {matches, ids, indices} = acc ->
          if MapSet.member?(ids, id) or MapSet.member?(indices, index),
            do: acc,
            else: {Map.put(matches, index, id), MapSet.put(ids, id), MapSet.put(indices, index)}
        end
      )

    tracks =
      state.tracks
      |> Enum.flat_map(fn {id, track} ->
        if track.missed < rule.max_missed,
          do: [{id, %{track | missed: track.missed + 1, hits: 0}}],
          else: []
      end)
      |> Map.new()

    {tracks, next_id, observed} =
      Enum.reduce(detections, {tracks, state.next_id, []}, fn {detection, index},
                                                              {tracks, next_id, observed} ->
        id = Map.get(matches, index, next_id)
        previous = Map.get(state.tracks, id)

        if previous != nil or map_size(tracks) < state.max_tracks do
          point = {detection.bbox.cx, detection.bbox.cy + detection.bbox.h / 2}
          velocity = if previous, do: delta(point, previous.point), else: {0, 0}

          track = %{
            id: id,
            bbox: detection.bbox,
            point: point,
            velocity: velocity,
            confidence: detection.confidence,
            object: detection.object,
            missed: 0,
            hits: if(previous, do: previous.hits + 1, else: 1),
            crossing: if(previous, do: previous.crossing, else: nil)
          }

          {Map.put(tracks, id, track), max(next_id, id + 1), [id | observed]}
        else
          {tracks, next_id, observed}
        end
      end)

    {%{state | tracks: tracks, next_id: next_id}, Enum.reverse(observed)}
  end

  defp delta({x, y}, {px, py}), do: {x - px, y - py}

  defp cost(track, detection) do
    {vx, vy} = track.velocity
    predicted = %{track.bbox | cx: track.bbox.cx + vx, cy: track.bbox.cy + vy}
    b = detection.bbox
    distance = :math.sqrt((predicted.cx - b.cx) ** 2 + (predicted.cy - b.cy) ** 2)
    overlap = iou(predicted, b)
    if distance <= 0.15 or overlap >= 0.1, do: distance * 3 + (1 - overlap) * 0.4, else: 2.0
  end

  defp iou(a, b) do
    width = max(0, min(a.cx + a.w / 2, b.cx + b.w / 2) - max(a.cx - a.w / 2, b.cx - b.w / 2))
    height = max(0, min(a.cy + a.h / 2, b.cy + b.h / 2) - max(a.cy - a.h / 2, b.cy - b.h / 2))
    intersection = width * height
    intersection / max(0.000001, a.w * a.h + b.w * b.h - intersection)
  end
end

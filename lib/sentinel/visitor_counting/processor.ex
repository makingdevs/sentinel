defmodule Sentinel.VisitorCounting.Processor do
  @moduledoc "Pure fresh-result processing. Events share the submitted frame binary without encoding or IO."
  alias Sentinel.VisitorCounting.{Crossing, Tracker}

  def process(tracker, objects, frame, rule, session) do
    {tracker, observed} = Tracker.update(tracker, objects, {frame.width, frame.height}, rule)

    Enum.reduce(observed, {tracker, []}, fn id, {tracker, events} ->
      {track, crossing} = Crossing.step(Map.fetch!(tracker.tracks, id), rule)
      tracker = %{tracker | tracks: Map.put(tracker.tracks, id, track)}

      {tracker, add_event(events, crossing, track, frame, rule, session)}
    end)
  end

  defp add_event(events, nil, _track, _frame, _rule, _session), do: events

  defp add_event(events, crossing, track, frame, rule, session) do
    identity = {rule.camera_id, rule.revision, session, track.id, crossing.crossing_number}
    key = :crypto.hash(:sha256, :erlang.term_to_binary(identity)) |> Base.encode16(case: :lower)

    attrs =
      Map.merge(crossing, %{
        camera_id: rule.camera_id,
        rule_revision: rule.revision,
        tracking_session_id: session,
        track_id: track.id,
        confidence: track.confidence,
        bbox: track.bbox,
        crossed_at: frame.crossed_at,
        dedupe_key: key
      })

    [%{attrs: attrs, frame: frame, object: track.object} | events]
  end
end

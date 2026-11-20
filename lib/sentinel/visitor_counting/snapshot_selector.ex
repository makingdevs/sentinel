defmodule Sentinel.VisitorCounting.SnapshotSelector do
  @moduledoc "Freeze a bounded cache selection at writer admission using same-node receipt time."
  alias Sentinel.VisitorCounting.SnapshotSource

  def freeze(%{attrs: attrs, frame: frame} = event) do
    result = select(attrs.camera_id, frame, SnapshotSource.read(attrs.camera_id))
    tracking = %{tracking_width: frame.width, tracking_height: frame.height}

    case result do
      {:ok, image} ->
        metadata = %{
          snapshot_quality: "primary",
          snapshot_received_at: image.received_at,
          snapshot_width: image.width,
          snapshot_height: image.height,
          snapshot_fallback_reason: nil
        }

        event
        |> Map.drop([:frame, :object])
        |> Map.put(:jpeg, image.jpeg)
        |> Map.put(:attrs, Map.merge(attrs, Map.merge(tracking, metadata)))

      {:error, reason} ->
        metadata = %{
          snapshot_quality: "secondary",
          snapshot_received_at: Map.get(frame, :crossed_at, attrs.crossed_at),
          snapshot_width: frame.width,
          snapshot_height: frame.height,
          snapshot_fallback_reason: reason
        }

        Map.put(event, :attrs, Map.merge(attrs, Map.merge(tracking, metadata)))
    end
  end

  def select(camera, frame, {:ok, cache}) do
    cond do
      Map.get(frame, :snapshot_generation) == nil ->
        {:error, "missing"}

      frame.snapshot_generation != cache.generation ->
        {:error, "generation_mismatch"}

      cache.frames == [] ->
        {:error, cache.reason || "missing"}

      true ->
        candidates =
          Enum.filter(
            cache.frames,
            &(&1.camera_id == camera and &1.received_mono <= frame.captured_at)
          )

        case Enum.max_by(candidates, & &1.received_mono, fn -> nil end) do
          nil ->
            {:error, "future"}

          image ->
            if frame.captured_at - image.received_mono <= 750 and
                 System.monotonic_time(:millisecond) - image.received_mono <= 3_000,
               do: {:ok, image},
               else: {:error, "stale"}
        end
    end
  end

  def select(_, _, {:error, reason}) when reason in [:missing, :unavailable],
    do: {:error, Atom.to_string(reason)}
end

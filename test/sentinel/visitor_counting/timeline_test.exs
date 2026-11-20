defmodule Sentinel.VisitorCounting.TimelineTest do
  use Sentinel.DataCase, async: false
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.Timeline

  defp event(key, seconds, camera \\ "a", extra \\ %{}) do
    attrs = %{
      camera_id: camera,
      rule_revision: 1,
      crossed_at: DateTime.add(~U[2026-11-19 06:00:00.000000Z], seconds),
      direction: "entry",
      tracking_session_id: "timeline",
      track_id: 1,
      crossing_number: 1,
      confidence: 0.9,
      bbox: %{},
      snapshot_key: key,
      dedupe_key: key
    }

    {:ok, event, :inserted} = VisitorCounting.create_event(Map.merge(attrs, extra))
    event
  end

  test "full-day grouping handles boundaries, ties, cameras and filters before pagination" do
    first = event("a0", 0)
    event("a120", 120)
    event("a120tie", 120)
    event("a241", 241)
    event("b100", 100, "b")
    event("before", -1)
    event("after", 86_400)
    event("exit", 10, "a", %{direction: "exit"})
    assert {:ok, data} = Timeline.activity("2026-11-19", %{"direction" => "entry"})
    assert data.image_count == 5
    assert data.group_count == 3
    assert length(data.bins) == 288
    assert Enum.sum(Enum.map(data.bins, & &1.count)) == 5
    first_bin = Enum.at(data.bins, 0)
    assert first_bin.count == 5
    assert Map.new(first_bin.cameras, &{&1.camera_id, &1.count}) == %{"a" => 4, "b" => 1}
    assert Enum.sum(Enum.map(first_bin.cameras, & &1.count)) == first_bin.count
    assert Enum.map(data.groups, & &1.image_count) == [3, 1, 1]

    assert {:ok, images} =
             Timeline.images("2026-11-19", %{"direction" => "entry"}, {:group, first.id})

    assert length(images) == 3
    assert hd(images).id == first.id
    assert {:ok, []} = Timeline.images("2026-11-19", %{"camera_id" => "b"}, {:group, first.id})
    assert {:error, :invalid_day} = Timeline.activity("bad")
    assert {:error, :invalid_selection} = Timeline.images("2026-11-19", %{}, {:bin, 288})
  end

  test "group and image pages do not truncate totals and receipt time wins" do
    for n <- 0..29, do: event("group#{n}", n * 121)
    for n <- 0..29, do: event("dense#{n}", 5000, "b")

    event("received", -1, "c", %{
      snapshot_quality: "primary",
      snapshot_received_at: ~U[2026-11-19 07:00:00.000000Z],
      snapshot_width: 1920,
      snapshot_height: 1080
    })

    assert {:ok, data} = Timeline.activity("2026-11-19")
    assert data.group_count == 32
    assert data.image_count == 61
    assert length(data.groups) == 24
    assert {:ok, second} = Timeline.activity("2026-11-19", %{}, 2)
    assert length(second.groups) == 8
    assert Enum.sum(Enum.map(data.groups ++ second.groups, & &1.image_count)) == 61
    assert {:ok, page} = Timeline.images("2026-11-19", %{"camera_id" => "b"})
    assert length(page) == 24
    assert {:ok, page2} = Timeline.images("2026-11-19", %{"camera_id" => "b"}, nil, 2)
    assert length(page2) == 6
  end

  @tag timeout: 60_000
  test "synthetic volume is aggregated in SQL and uses effective-time indexes" do
    Repo.query!("""
    INSERT INTO passage_events
      (camera_id, rule_revision, crossed_at, direction, tracking_session_id, track_id,
       crossing_number, confidence, bbox, snapshot_key, dedupe_key, inserted_at)
    SELECT 'volume-' || (n % 4), 1,
      timestamp '2026-11-01' + n * interval '10 seconds',
      CASE WHEN n % 2 = 0 THEN 'entry' ELSE 'exit' END,
      'synthetic', 1, 1, 0.9, '{}'::jsonb, 'not-read', 'volume-' || n, now()
    FROM generate_series(0, 199999) n
    """)

    assert {:ok, data} = Timeline.activity("2026-11-19")
    assert data.image_count == 8640
    assert Enum.sum(Enum.map(data.bins, & &1.count)) == 8640
    assert Enum.sum(Enum.map(data.groups, & &1.image_count)) == 8640

    plan =
      Repo.query!(
        """
        EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
        SELECT id FROM passage_events
        WHERE COALESCE(snapshot_received_at, crossed_at) >= $1
          AND COALESCE(snapshot_received_at, crossed_at) < $2
        """,
        [~N[2026-11-19 06:00:00], ~N[2026-11-20 06:00:00]]
      )

    assert inspect(plan.rows) =~ "effective_image_at"

    assert {:ok, 8640, _} =
             Repo.delete_all(
               from e in Sentinel.VisitorCounting.PassageEvent,
                 where:
                   e.crossed_at >= ^~U[2026-11-19 06:00:00Z] and
                     e.crossed_at < ^~U[2026-11-20 06:00:00Z]
             )
             |> then(fn {count, rows} -> {:ok, count, rows} end)

    assert {:ok, empty} = Timeline.activity("2026-11-19")
    assert empty.image_count == 0
  end
end

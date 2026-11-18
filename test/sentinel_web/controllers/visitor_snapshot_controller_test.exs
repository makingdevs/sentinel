defmodule SentinelWeb.VisitorSnapshotControllerTest do
  use SentinelWeb.ConnCase, async: false
  alias Sentinel.VisitorCounting.{PassageEvent, Persistence, Snapshots}
  import Ecto.Query

  setup do
    previous = Application.get_env(:sentinel, :visitor_counting, [])
    root = "/private/tmp/visitor-endpoint-#{System.unique_integer([:positive])}"
    Application.put_env(:sentinel, :visitor_counting, snapshot_root: root)
    {:ok, jpeg} = Image.new!(32, 32) |> Image.write(:memory, suffix: ".jpg")

    {:ok, event, :inserted} =
      Persistence.save(
        %{
          camera_id: "division-1",
          rule_revision: 1,
          crossed_at: DateTime.utc_now(),
          direction: "entry",
          tracking_session_id: "session",
          track_id: 1,
          crossing_number: 1,
          confidence: 0.9,
          bbox: %{cx: 0.5},
          dedupe_key: "endpoint"
        },
        jpeg
      )

    on_exit(fn ->
      Application.put_env(:sentinel, :visitor_counting, previous)
      File.rm_rf!(root)
    end)

    %{event: event, jpeg: jpeg}
  end

  test "local capture is DB-resolved and never cached", %{conn: conn, event: event, jpeg: jpeg} do
    conn = get(conn, ~p"/visitors/events/#{event.id}/snapshot")
    assert response(conn, 200) == jpeg
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "nonlocal, missing, oversized ID and unsafe DB key are rejected", %{
    conn: conn,
    event: event
  } do
    assert response(
             get(
               %{conn | remote_ip: {203, 0, 113, 1}},
               ~p"/visitors/events/#{event.id}/snapshot"
             ),
             403
           )

    assert response(get(conn, "/visitors/events/999999999999999999999999/snapshot"), 404)
    assert response(get(conn, "/visitors/events/missing/snapshot"), 404)

    Sentinel.Repo.update_all(from(e in PassageEvent, where: e.id == ^event.id),
      set: [snapshot_key: "../../etc/passwd"]
    )

    assert response(get(conn, ~p"/visitors/events/#{event.id}/snapshot"), 404)
  end

  test "symlink cannot serve files outside private root", %{conn: conn, event: event} do
    {:ok, path} = Snapshots.path(event.snapshot_key)
    File.rm!(path)
    File.ln_s!("/etc/passwd", path)
    assert response(get(conn, ~p"/visitors/events/#{event.id}/snapshot"), 404)
  end
end

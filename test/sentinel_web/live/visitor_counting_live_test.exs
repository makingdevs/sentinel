defmodule SentinelWeb.VisitorCountingLiveTest do
  use SentinelWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Sentinel.VisitorCounting

  test "filters and totals come from DB, page changes bound the stream", %{conn: conn} do
    for i <- 1..25, do: event("entry", "division-1", i)
    exit = event("exit", "division-2", 26)
    {:ok, view, _} = live(conn, ~p"/visitors")
    assert has_element?(view, "#entry-total", "25")
    assert has_element?(view, "#exit-total", "1")
    assert has_element?(view, "#visitor-next:not([disabled])")
    view |> element("#visitor-next") |> render_click()
    assert has_element?(view, "#visitor-page", "2")

    view
    |> form("#visitor-filters", filters: %{camera_id: "division-2", direction: "exit"})
    |> render_submit()

    assert has_element?(view, "#passage-link-#{exit.id}")
    assert has_element?(view, "#entry-total", "0")
    assert has_element?(view, "#exit-total", "1")
    assert has_element?(view, "#visitor-page", "1")
    refute has_element?(view, "#visitor-next:not([disabled])")
    view |> element("#passage-link-#{exit.id}") |> render_click()
    assert has_element?(view, "#passage-detail")
  end

  test "PubSub re-queries current filters, invalid dates preserve results", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/visitors")
    assert has_element?(view, "#passage-empty")
    saved = event("entry", "division-1", 1)
    send(view.pid, {:passage_saved, saved.id})
    assert has_element?(view, "#passage-link-#{saved.id}")

    view
    |> form("#visitor-filters", filters: %{from: "2026-11-20", until: "2026-11-01"})
    |> render_submit()

    assert has_element?(view, "#passage-link-#{saved.id}")

    assert has_element?(view, "#visitor-filters [phx-feedback-for]") or
             has_element?(view, "#visitor-filters p")
  end

  test "HTTP and connected LiveView reject nonlocal peers", %{conn: conn} do
    assert %{status: 403} = get(%{conn | remote_ip: {203, 0, 113, 1}}, ~p"/visitors")
    conn = put_private(conn, :live_view_connect_info, %{peer_data: %{address: {203, 0, 113, 1}}})
    assert {:error, {:redirect, %{to: "/cameras"}}} = live(conn, ~p"/visitors")
  end

  defp event(direction, camera, number) do
    {:ok, event, :inserted} =
      VisitorCounting.create_event(%{
        camera_id: camera,
        rule_revision: 1,
        crossed_at: DateTime.utc_now(),
        direction: direction,
        tracking_session_id: "session",
        track_id: number,
        crossing_number: 1,
        confidence: 0.9,
        bbox: %{cx: 0.5, cy: 0.5, w: 0.1, h: 0.2},
        snapshot_key: Sentinel.VisitorCounting.Snapshots.new_key(),
        dedupe_key: "lv-#{number}"
      })

    event
  end
end

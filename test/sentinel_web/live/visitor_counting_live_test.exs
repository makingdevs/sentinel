defmodule SentinelWeb.VisitorCountingLiveTest do
  use SentinelWeb.ConnCase, async: true
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  import Ecto.Query
  alias Sentinel.Repo
  import Phoenix.LiveViewTest
  alias Sentinel.VisitorCounting

  test "filters and totals come from DB, page changes bound the stream", %{conn: conn} do
    for i <- 1..25, do: event("entry", "division-1", i)
    exit = event("exit", "division-2", 26)
    {:ok, view, _} = live(conn, ~p"/visitors")
    render_async(view)
    assert has_element?(view, "#entry-total", "25")
    assert has_element?(view, "#exit-total", "1")
    assert has_element?(view, "#visitor-next:not([disabled])")
    view |> element("#visitor-next") |> render_click()
    render_async(view)
    assert has_element?(view, "#visitor-page", "2")

    view
    |> form("#visitor-filters", filters: %{camera_id: "division-2", direction: "exit"})
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#passage-link-#{exit.id}")
    assert has_element?(view, "#entry-total", "0")
    assert has_element?(view, "#exit-total", "1")
    assert has_element?(view, "#visitor-page", "1")
    refute has_element?(view, "#visitor-next:not([disabled])")
    view |> element("#passage-link-#{exit.id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#passage-detail")
  end

  test "PubSub re-queries current filters, invalid dates preserve results", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/visitors")
    render_async(view)
    assert has_element?(view, "#passage-empty")
    saved = event("entry", "division-1", 1)
    send(view.pid, {:passage_saved, saved.id})
    state = :sys.get_state(view.pid)
    {_, token} = state.socket.assigns.refresh_timer
    send(view.pid, {:refresh, token})
    render_async(view)
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

  test "daily groups and bins retain URL context through detail and pagination", %{conn: conn} do
    first = event("entry", "division-1", 1, ~U[2026-11-19 12:00:00.000000Z])

    for n <- 2..30 do
      e = event("entry", "division-1", n)

      Repo.update_all(from(row in Sentinel.VisitorCounting.PassageEvent, where: row.id == ^e.id),
        set: [crossed_at: DateTime.add(first.crossed_at, n * 121)]
      )
    end

    day = Date.to_iso8601(DateTime.to_date(first.crossed_at))
    {:ok, view, _} = live(conn, "/visitors?mode=daily&day=#{day}&camera_id=division-1")
    render_async(view)
    assert has_element?(view, "#daily-timeline")
    assert has_element?(view, "#density-bin-0[aria-label]")
    assert has_element?(view, "#density-bin-287")
    assert has_element?(view, "#visitor-groups-next:not([disabled])")
    view |> element("#visitor-groups-next") |> render_click()
    render_async(view)
    assert has_element?(view, "#visitor-groups-next[disabled]")
    view |> element("#visitor-groups-previous") |> render_click()
    render_async(view)
    view |> element("#visitor-group-#{first.id}") |> render_click()
    render_async(view)
    render_async(view)
    assert has_element?(view, "#visitor-group-#{first.id}[aria-pressed=true]")
    assert has_element?(view, "#visitor-reset-selection")
    refute has_element?(view, "#visitor-next:not([disabled])")

    assert has_element?(
             view,
             "#passage-link-#{first.id}[href*='mode=daily'][href*='selection_from']"
           )

    view |> element("#passage-link-#{first.id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#passage-detail")
    assert has_element?(view, "#visitor-close-detail[href*='group=']")
    view |> element("#visitor-close-detail") |> render_click()
    render_async(view)
    refute has_element?(view, "#passage-detail")
    view |> element("#visitor-reset-selection") |> render_click()
    render_async(view)
    assert has_element?(view, "#visitor-next:not([disabled])")
  end

  test "coalesces bursts and reconciles a deleted selected group without new crossings", %{
    conn: conn
  } do
    saved = event("entry", "division-1", 1)
    day = Sentinel.LocalTime.today()
    {:ok, view, _} = live(conn, "/visitors?mode=daily&day=#{day}&group=#{saved.id}")
    render_async(view)
    render_async(view)
    assert has_element?(view, "#visitor-reset-selection")
    for _ <- 1..100, do: send(view.pid, {:passage_saved, saved.id})
    state = :sys.get_state(view.pid)
    {timer, token} = state.socket.assigns.refresh_timer
    assert is_reference(timer)
    send(view.pid, {:passage_saved, saved.id})
    assert :sys.get_state(view.pid).socket.assigns.refresh_timer == {timer, token}
    Repo.delete!(saved)
    send(view.pid, :passages_pruned)
    send(view.pid, {:refresh, token})
    render_async(view)
    render_async(view)
    refute has_element?(view, "#visitor-reset-selection")
    assert has_element?(view, "#passage-empty")
    assert has_element?(view, "#daily-timeline")
  end

  test "malformed selection and URL values preserve a safe page", %{conn: conn} do
    saved = event("entry", "division-1", 1)

    {:ok, view, _} =
      live(
        conn,
        "/visitors?mode=daily&day=#{Sentinel.LocalTime.today()}&group=999999999999999999999999999999&page=bad"
      )

    render_async(view)
    render_async(view)
    assert has_element?(view, "#passage-link-#{saved.id}")
    refute has_element?(view, "#visitor-query-error")
    view |> element("#density-bin-0") |> render_click()
    render_async(view)
    assert has_element?(view, "#density-bin-0[aria-pressed=true]")
    view |> element("#visitor-reset-selection") |> render_click()
    render_async(view)
    assert has_element?(view, "#passage-link-#{saved.id}")
    assert VisitorCounting.totals().entry == 1
  end

  test "provenance differentiates full-frame primary, fallback and historical captures", %{
    conn: conn
  } do
    historical = event("entry", "division-1", 1)
    primary = event("entry", "division-1", 2)
    fallback = event("entry", "division-1", 3)

    for {e, quality, reason} <- [{primary, "primary", nil}, {fallback, "secondary", "stale"}] do
      Repo.update!(
        Ecto.Changeset.change(e,
          snapshot_quality: quality,
          snapshot_fallback_reason: reason,
          snapshot_received_at: e.crossed_at,
          snapshot_width: 1920,
          snapshot_height: 1080
        )
      )
    end

    {:ok, view, _} = live(conn, "/visitors")
    render_async(view)
    assert has_element?(view, "#snapshot-provenance-card-#{historical.id}", "histórica")
    assert has_element?(view, "#snapshot-provenance-card-#{primary.id}", "Primaria")
    assert has_element?(view, "#snapshot-provenance-card-#{fallback.id}", "respaldo")
    view |> element("#passage-link-#{primary.id}") |> render_click()
    render_async(view)
    assert has_element?(view, "#snapshot-provenance-detail-#{primary.id}", "sin recuadro")
  end

  test "rapid URL changes keep only the current camera query result", %{conn: conn} do
    first = event("entry", "division-1", 1)
    second = event("exit", "division-2", 2)
    {:ok, view, _} = live(conn, "/visitors")
    render_patch(view, "/visitors?mode=daily&camera_id=division-2")
    render_patch(view, "/visitors?mode=daily&camera_id=division-1")
    render_async(view)
    render_async(view)
    assert has_element?(view, "#passage-link-#{first.id}")
    refute has_element?(view, "#passage-link-#{second.id}")
    assert has_element?(view, "#visitor-filters select option[value='division-1'][selected]")
  end

  test "list and map selection params fall back to the full day", %{conn: conn} do
    saved = event("entry", "division-1", 1)

    for query <- ["group[]=1", "bin[value]=1"] do
      {:ok, view, _} = live(conn, "/visitors?mode=daily&" <> query)
      render_async(view)
      render_async(view)
      assert has_element?(view, "#passage-link-#{saved.id}")
      refute has_element?(view, "#visitor-query-error")
    end
  end

  defp event(direction, camera, number, crossed_at \\ DateTime.utc_now()) do
    {:ok, event, :inserted} =
      VisitorCounting.create_event(%{
        camera_id: camera,
        rule_revision: 1,
        crossed_at: crossed_at,
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

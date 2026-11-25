defmodule SentinelWeb.VisitorCountingLiveTest do
  use SentinelWeb.ConnCase, async: false
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  import Ecto.Query
  alias Sentinel.Repo
  alias Sentinel.Monitoring.Camera
  import Phoenix.LiveViewTest
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.Manager

  setup context do
    if context[:daily] do
      config = Application.fetch_env!(:sentinel, :visitor_counting)

      Application.put_env(
        :sentinel,
        :visitor_counting,
        Keyword.put(config, :pipeline_module, Sentinel.TestMediaPipeline)
      )

      Application.put_env(:sentinel, :media_test_owner, self())

      on_exit(fn ->
        Application.put_env(:sentinel, :visitor_counting, config)
        Application.delete_env(:sentinel, :media_test_owner)
      end)

      start_supervised!(
        {DynamicSupervisor, name: Sentinel.TestMediaSupervisor, strategy: :one_for_one}
      )

      for id <- ~w(division-1 division-2) do
        camera_source_fixture(id, "secundaria", "rtsp://example.test/#{id}")
        assert {:ok, _} = VisitorCounting.configure_rule(id, %{enabled: true})
      end

      start_supervised!({Manager, max_cameras: 2})

      pipelines =
        for id <- ~w(division-1 division-2), into: %{} do
          assert_receive {:media_started, pipeline, %{owner: owner, rule: %{camera_id: ^id}}}
          send(owner, {:analytics_status, pipeline, :active})
          _ = :sys.get_state(owner)
          assert Manager.status(id) == :active
          {id, {owner, pipeline}}
        end

      {:ok, pipelines: pipelines}
    else
      :ok
    end
  end

  test "mode navigation marks only the selected mode", %{conn: conn} do
    {:ok, view, _} = live(conn, "/visitors?mode=range")
    assert has_element?(view, "#visitor-mode-range[aria-current=page]")
    refute has_element?(view, "#visitor-mode-daily[aria-current]")

    view |> element("#visitor-mode-daily") |> render_click()
    assert has_element?(view, "#visitor-mode-daily[aria-current=page]")
    refute has_element?(view, "#visitor-mode-range[aria-current]")

    view |> element("#visitor-mode-range") |> render_click()
    assert has_element?(view, "#visitor-mode-range[aria-current=page]")
    refute has_element?(view, "#visitor-mode-daily[aria-current]")
  end

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

  @tag :daily
  test "open history updates channel colors while preserving filters and detail", %{conn: conn} do
    capture = event("entry", "division-1", 1, ~U[2026-11-19 12:00:00.000000Z])

    {:ok, view, _} =
      live(
        conn,
        "/visitors/events/#{capture.id}?mode=daily&day=2026-11-19&camera_id=division-1"
      )

    render_async(view, 1_000)

    assert {:ok, _} =
             Sentinel.Monitoring.save_camera(%{
               id: "division-1",
               branch: "División",
               label: "Entrada principal",
               color: "rose"
             })

    render_async(view, 1_000)

    for selector <- [
          "#selected-channel-color",
          "#timeline-camera-legend",
          "#visitor-group-#{capture.id}",
          "#passage-link-#{capture.id}",
          "#passage-detail"
        ] do
      assert has_element?(view, "#{selector} [style*='#fb7185']")
      assert has_element?(view, selector, "Entrada principal")
    end

    assert has_element?(view, "#visitor-close-detail[href*='camera_id=division-1']")
  end

  @tag :daily
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
    assert has_element?(view, "#timeline-camera-division-1", "30 imágenes")
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

  @tag :daily
  test "catalog changes refresh daily labels without changing active URL filters", %{conn: conn} do
    saved = event("entry", "division-1", 1, ~U[2026-11-19 12:00:00.000000Z])
    day = Date.to_iso8601(DateTime.to_date(saved.crossed_at))
    {:ok, view, _} = live(conn, "/visitors?mode=daily&day=#{day}&camera_id=division-1")
    render_async(view)
    assert has_element?(view, "#visitor-group-#{saved.id}", "Cámara 1")

    camera = Repo.get!(Camera, "division-1")
    Repo.update!(Ecto.Changeset.change(camera, label: "Entrada", color: "rose"))
    send(view.pid, {:camera_changed, camera.id})
    _ = :sys.get_state(view.pid)
    render_async(view)

    assert has_element?(view, "#visitor-group-#{saved.id}", "Entrada")
    assert has_element?(view, "#visitor-group-#{saved.id} [style='background-color: #fb7185']")
    assert has_element?(view, "#visitor-filters")
  end

  @tag :daily
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

  @tag :daily
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

  @tag :daily
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

  @tag :daily
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

  @tag :daily
  test "daily removes a stopped camera from every result and preserves its range history", %{
    conn: conn,
    pipelines: pipelines
  } do
    active = event("entry", "division-1", 1)
    stopped = event("entry", "lavirgen-1", 2)
    day = Sentinel.LocalTime.today()
    {:ok, view, _} = live(conn, "/visitors?mode=daily&day=#{day}&direction=entry")
    render_async(view)

    assert has_element?(view, "#timeline-camera-division-1", "División · Cámara 1")
    assert has_element?(view, "#entry-total dd", "1")
    assert has_element?(view, "#exit-total dd", "0")
    assert has_element?(view, "#visitor-group-#{active.id} time")
    assert has_element?(view, "#passage-link-#{active.id} time")

    for id <- ~w(lavirgen-1 division-2) do
      refute has_element?(view, "#timeline-camera-#{id}")
      refute has_element?(view, "#visitor-filters option[value='#{id}']")
    end

    refute has_element?(view, "#visitor-group-#{stopped.id}")
    refute has_element?(view, "#passage-link-#{stopped.id}")

    exit = event("exit", "division-2", 3)
    saved = event("entry", "division-2", 4)
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "visitor_events", {:passage_saved, saved.id})
    flush_refresh(view)
    assert has_element?(view, "#timeline-camera-division-2")
    assert has_element?(view, "#entry-total dd", "2")
    refute has_element?(view, "#passage-link-#{exit.id}")

    render_patch(view, "/visitors?mode=daily&day=#{day}&camera_id=division-1&group=#{active.id}")
    render_async(view)
    render_async(view)
    assert has_element?(view, "#visitor-reset-selection")

    {owner, pipeline} = Map.fetch!(pipelines, "division-1")
    send(owner, {:analytics_status, pipeline, :loading})
    _ = :sys.get_state(owner)
    assert Manager.status("division-1") == :loading
    flush_refresh(view)
    render_async(view)
    assert has_element?(view, "#visitor-selection-notice")
    assert has_element?(view, "#visitor-filters option[value='division-1'][selected]")
    assert has_element?(view, "#visitor-groups-empty", "La cámara seleccionada")
    assert has_element?(view, "#entry-total dd", "0")
    assert has_element?(view, "#visitor-next[disabled]")
    refute has_element?(view, "#timeline-camera-legend")
    refute has_element?(view, "#visitor-reset-selection")
    refute has_element?(view, "#passage-link-#{active.id}")

    view |> element("#visitor-mode-range") |> render_click()
    render_async(view)
    assert has_element?(view, "#passage-link-#{active.id}")
    assert has_element?(view, "#entry-total dd", "1")
  end

  defp flush_refresh(view) do
    {_, token} = :sys.get_state(view.pid).socket.assigns.refresh_timer
    send(view.pid, {:refresh, token})
    render_async(view)
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

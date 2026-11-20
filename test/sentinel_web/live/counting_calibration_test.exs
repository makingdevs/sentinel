defmodule SentinelWeb.CountingCalibrationTest do
  use SentinelWeb.ConnCase, async: true
  import Sentinel.MonitoringFixtures
  setup :camera_catalog_fixture_setup

  defp camera_catalog_fixture_setup(_context), do: camera_catalog_fixture()

  import Phoenix.LiveViewTest
  alias Sentinel.VisitorCounting

  test "calibrates/saves validated settings without replacing the viewer", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/cameras")

    view
    |> form("#camera-selection-form", selection: %{camera_id: "division-1"})
    |> render_submit()

    view |> element("#configure-counting-division-1") |> render_click()

    assert has_element?(
             view,
             "#calibration-division-1-secundaria-0[phx-hook=CountingLine][phx-update=ignore]"
           )

    render_hook(view, "line", %{id: "division-1", line: %{x1: 0.2, y1: 0.45, x2: 0.8, y2: 0.45}})

    view
    |> form("#counting-rule-division-1",
      rule: %{engine: "elixir", entry_direction: "negative", confidence: "0.7", enabled: false}
    )
    |> render_submit()

    rule = VisitorCounting.get_rule("division-1")
    assert rule.x1 == 0.2
    assert rule.y1 == 0.45
    assert rule.x2 == 0.8
    assert rule.engine == "elixir"
    assert rule.entry_direction == "negative"
    assert rule.confidence == 0.7
    refute rule.enabled
    assert has_element?(view, "#player-division-1-secundaria-0")
    view |> form("#counting-rule-division-1", rule: %{x1: "-1"}) |> render_submit()
    assert VisitorCounting.get_rule("division-1").x1 == 0.2
    view |> element("#close-counting-division-1") |> render_click()
    refute has_element?(view, "#calibration-division-1-secundaria-0")
    assert has_element?(view, "#counting-status-division-1")
    assert has_element?(view, "#counting-status-division-1 .rounded-full", "Deshabilitado")
  end

  test "two open calibrations have separate controls and save independently", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/cameras")

    for camera_id <- ["division-1", "division-2"] do
      view
      |> form("#camera-selection-form", selection: %{camera_id: camera_id})
      |> render_submit()

      view |> element("#configure-counting-#{camera_id}") |> render_click()
    end

    for camera_id <- ["division-1", "division-2"],
        field <- ~w(x1 y1 x2 y2 engine entry_direction confidence enabled) do
      assert has_element?(
               view,
               ~s(#counting-rule-#{camera_id} #counting-rule-#{camera_id}_#{field}[name="rule[#{field}]"])
             )
    end

    view
    |> form("#counting-rule-division-2", rule: %{engine: "elixir"})
    |> render_submit()

    assert VisitorCounting.get_rule("division-2").engine == "elixir"
    refute VisitorCounting.get_rule("division-1")
    assert has_element?(view, "#counting-rule-division-1_engine option[value=python][selected]")
  end

  test "remote viewers cannot forge calibration writes", %{conn: conn} do
    conn = put_private(conn, :live_view_connect_info, %{peer_data: %{address: {203, 0, 113, 1}}})
    {:ok, view, _} = live(%{conn | remote_ip: {203, 0, 113, 1}}, ~p"/cameras")

    view
    |> form("#camera-selection-form", selection: %{camera_id: "division-1"})
    |> render_submit()

    refute has_element?(view, "#configure-counting-division-1")
    render_hook(view, "save-counting", %{id: "division-1", rule: %{enabled: true}})
    refute VisitorCounting.get_rule("division-1")
  end
end

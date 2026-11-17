defmodule SentinelWeb.CameraLiveTest do
  use SentinelWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "starts empty with grouped choices and resets on a fresh visit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cameras")
    assert has_element?(view, "#camera-grid[phx-update=stream]")
    assert has_element?(view, "#camera-empty")
    refute has_element?(view, "#camera-grid video")

    assert has_element?(
             view,
             "#camera-select optgroup[label='División'] option[value='division-1']"
           )

    assert has_element?(
             view,
             "#camera-select optgroup[label='La Virgen'] option[value='lavirgen-1']"
           )

    assert has_element?(view, "#clear-cameras[disabled]")
    add(view, "division-1")
    {:ok, fresh, _html} = live(conn, ~p"/cameras")
    refute has_element?(fresh, "#camera-grid video")
  end

  test "adds from both branches without duplicates and preserves other player identities", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/cameras")
    add(view, "division-1")

    assert has_element?(
             view,
             "#player-division-1-secundaria-0[phx-hook=HlsPlayer][phx-update=ignore]"
           )

    add(view, "lavirgen-1")
    add(view, "division-1")
    assert has_element?(view, "#player-division-1-secundaria-0")
    assert has_element?(view, "#player-lavirgen-1-secundaria-0")
    assert has_element?(view, "#camera-count", "2 / 8")

    refute has_element?(view, "#camera-grid article:nth-of-type(3)")
  end

  test "quality change and retry replace only the targeted player", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cameras")
    add(view, "division-1")
    add(view, "lavirgen-1")
    view |> form("#quality-division-1", quality: %{value: "principal"}) |> render_change()

    assert has_element?(
             view,
             "#player-division-1-principal-1[data-source='/hls/division-1/principal/index.m3u8']"
           )

    refute has_element?(view, "#player-division-1-secundaria-0")
    assert has_element?(view, "#player-lavirgen-1-secundaria-0")
    view |> element("#retry-division-1") |> render_click()
    assert has_element?(view, "#player-division-1-principal-2")
    refute has_element?(view, "#player-division-1-principal-1")
    assert has_element?(view, "#player-lavirgen-1-secundaria-0")
    view |> form("#quality-division-1", quality: %{value: "principal"}) |> render_change()
    assert has_element?(view, "#player-division-1-principal-2")
  end

  test "removes an individual card and clears all players", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cameras")
    add(view, "division-1")
    add(view, "lavirgen-1")
    view |> element("#remove-division-1") |> render_click()
    refute has_element?(view, "#cameras-division-1")
    assert has_element?(view, "#player-lavirgen-1-secundaria-0")
    view |> element("#clear-cameras") |> render_click()
    refute has_element?(view, "#camera-grid video")
    assert has_element?(view, "#clear-cameras[disabled]")
    add(view, "division-1")
    assert has_element?(view, "#player-division-1-secundaria-0")
  end

  test "supports all eight cameras and enforces the limit server-side", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cameras")
    for camera <- Sentinel.Monitoring.list_cameras(), do: add(view, camera.id)
    assert has_element?(view, "#camera-count", "8 / 8")
    assert has_element?(view, "#add-camera[disabled]")
    render_submit(view, "add", %{"selection" => %{"camera_id" => "ninth"}})
    assert has_element?(view, "#flash-error")
    refute has_element?(view, "#cameras-ninth")
  end

  test "invalid or malformed events do not add or change players", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cameras")
    render_submit(view, "add", %{"selection" => %{"camera_id" => "../private"}})
    refute has_element?(view, "#camera-grid video")
    assert has_element?(view, "#flash-error")
    add(view, "division-1")
    render_change(view, "quality", %{"id" => "division-1", "quality" => %{"value" => "invalid"}})
    render_change(view, "quality", %{"id" => "missing", "quality" => %{"value" => "principal"}})
    render_click(view, "retry", %{"id" => "missing"})
    render_click(view, "remove", %{"id" => "missing"})
    render_submit(view, "add", %{})
    assert has_element?(view, "#player-division-1-secundaria-0")
    refute has_element?(view, "#player-division-1-principal-1")
  end

  defp add(view, id) do
    view |> form("#camera-selection-form", selection: %{camera_id: id}) |> render_submit()
  end
end

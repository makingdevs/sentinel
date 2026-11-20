defmodule SentinelWeb.CameraCatalogLiveTest do
  use SentinelWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Sentinel.Repo
  alias Sentinel.Monitoring.{Camera, CameraSource}

  test "counting state labels separate disabled, offline, capacity and no events" do
    assert SentinelWeb.CameraCatalogLive.counting_text(%{counting_enabled: false}) ==
             "Deshabilitado"

    assert SentinelWeb.CameraCatalogLive.counting_text(%{
             counting_enabled: true,
             counting_status: :error
           }) == "Sin conexión"

    assert SentinelWeb.CameraCatalogLive.counting_text(%{
             counting_enabled: true,
             counting_status: :capacity
           }) == "Sin capacidad"

    assert SentinelWeb.CameraCatalogLive.counting_text(%{
             counting_enabled: true,
             counting_status: :active,
             last_capture: nil
           }) == "Contando, sin eventos registrados"
  end

  test "catalog is local-only and never renders saved RTSP credentials", %{conn: conn} do
    camera = Repo.insert!(%Camera{id: "division-1", branch: "División", label: "Cámara 1"})

    Repo.insert!(
      CameraSource.changeset(%CameraSource{camera_id: camera.id}, %{
        quality: "principal",
        url: "rtsp://user:secret@example.test/main"
      }),
      log: false
    )

    {:ok, view, html} = live(conn, ~p"/cameras/catalog")
    assert has_element?(view, "#camera-catalog-form")
    assert has_element?(view, "#camera-catalog-form input[type=password]")
    assert html =~ "Principal configurada"
    refute html =~ "secret"
    refute html =~ "example.test"

    remote_conn = %{conn | remote_ip: {203, 0, 113, 5}}
    assert %{status: 403} = get(remote_conn, ~p"/cameras/catalog")
  end

  test "catalog edits metadata and archives a channel", %{conn: conn} do
    Repo.insert!(%Camera{id: "division-1", branch: "División", label: "Cámara 1"})
    {:ok, view, _html} = live(conn, ~p"/cameras/catalog")
    view |> element("button[phx-click=edit][phx-value-id=division-1]") |> render_click()

    view
    |> form("#camera-catalog-form", camera: %{label: "Entrada", color: "rose"})
    |> render_submit()

    assert has_element?(view, "#camera-catalog-form")
    assert Repo.get!(Camera, "division-1").label == "Entrada"
    view |> element("button[phx-click=archive][phx-value-id=division-1]") |> render_click()
    assert Repo.get!(Camera, "division-1").archived_at
  end

  test "catalog shows persisted latest capture per channel", %{conn: conn} do
    Repo.insert!(%Camera{id: "division-1", branch: "División", label: "Cámara 1"})

    attrs = %{
      camera_id: "division-1",
      rule_revision: 1,
      crossed_at: ~U[2026-11-19 12:00:00.000000Z],
      direction: "entry",
      tracking_session_id: "catalog",
      track_id: 1,
      crossing_number: 1,
      confidence: 0.9,
      bbox: %{},
      snapshot_key: "catalog-snapshot",
      dedupe_key: "catalog-event",
      snapshot_received_at: ~U[2026-11-19 12:00:05.000000Z],
      snapshot_quality: "primary",
      snapshot_width: 1920,
      snapshot_height: 1080
    }

    assert {:ok, _event, :inserted} = Sentinel.VisitorCounting.create_event(attrs)
    {:ok, view, _html} = live(conn, ~p"/cameras/catalog")
    assert has_element?(view, "#camera-catalog-form")
    assert has_element?(view, "#catalog-camera-division-1 .rounded-full", "Deshabilitado")
    assert render(view) =~ "06:00:05"
  end
end

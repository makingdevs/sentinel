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

  test "catalog creates, edits, archives and restores a channel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cameras/catalog")

    view
    |> form("#camera-catalog-form",
      camera: %{id: "division-1", branch: "División", label: "Cámara 1"}
    )
    |> render_submit()

    assert has_element?(view, "#catalog-camera-division-1", "Cámara 1")
    view |> element("#edit-camera-division-1") |> render_click()

    view
    |> form("#camera-catalog-form", camera: %{label: "Entrada", color: "rose"})
    |> render_submit()

    assert has_element?(view, "#camera-catalog-form")
    assert Repo.get!(Camera, "division-1").label == "Entrada"
    assert has_element?(view, "#catalog-camera-division-1 [style*='#fb7185']")

    assert has_element?(
             view,
             "#catalog-camera-division-1 button[phx-click=archive][data-confirm]"
           )

    view |> element("button[phx-click=archive][phx-value-id=division-1]") |> render_click()
    assert Repo.get!(Camera, "division-1").archived_at
    view |> element("button[phx-click=restore][phx-value-id=division-1]") |> render_click()
    assert has_element?(view, "#edit-camera-division-1")
    assert is_nil(Repo.get!(Camera, "division-1").archived_at)
  end

  test "switching edit targets loads each saved branch and preserves it on save", %{conn: conn} do
    Repo.insert!(%Camera{id: "division-1", branch: "División", label: "Entrada"})
    Repo.insert!(%Camera{id: "lavirgen-1", branch: "La Virgen", label: "Entrada"})

    {:ok, view, _} = live(conn, ~p"/cameras/catalog")
    assert has_element?(view, "#catalog-branch-division-1", "División")
    assert has_element?(view, "#catalog-branch-lavirgen-1", "La Virgen")

    view |> element("#edit-camera-division-1") |> render_click()
    assert has_element?(view, "#camera-catalog-heading[tabindex='-1']", "Editar canal")
    assert has_element?(view, "#catalog-camera-branch[value='División']")

    view |> element("#edit-camera-lavirgen-1") |> render_click()
    assert has_element?(view, "#catalog-camera-branch[value='La Virgen']")

    view
    |> form("#camera-catalog-form", camera: %{label: "Entrada norte"})
    |> render_submit()

    assert %{branch: "La Virgen", label: "Entrada norte"} = Repo.get!(Camera, "lavirgen-1")
  end

  test "catalog shows persisted latest capture per channel", %{conn: conn} do
    Repo.insert!(%Camera{id: "division-1", branch: "División", label: "Cámara 1"})
    {:ok, view, _html} = live(conn, ~p"/cameras/catalog")
    assert has_element?(view, "#catalog-camera-division-1", "Sin captura persistida")
    view |> element("#edit-camera-division-1") |> render_click()

    view
    |> form("#camera-catalog-form", camera: %{label: "Edición sin guardar"})
    |> render_change()

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

    assert {:ok, event, :inserted} = Sentinel.VisitorCounting.create_event(attrs)
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "visitor_events", {:passage_saved, event.id})
    assert has_element?(view, "#camera-catalog-form input[value='Edición sin guardar']")
    assert has_element?(view, "#catalog-camera-division-1 .rounded-full", "Deshabilitado")
    assert has_element?(view, "#catalog-camera-division-1 time[title$='06:00:05 CST']")
    expected = Sentinel.LocalTime.relative(event.snapshot_received_at, DateTime.utc_now())
    assert has_element?(view, "#catalog-camera-division-1 time", expected)
  end
end

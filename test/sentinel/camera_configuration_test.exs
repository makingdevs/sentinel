defmodule Sentinel.CameraConfigurationTest do
  use Sentinel.DataCase, async: true
  alias Sentinel.Monitoring.{Camera, CameraSource}
  alias Sentinel.Monitoring
  import ExUnit.CaptureLog

  test "metadata validates required fields and keeps historical string IDs" do
    refute Camera.changeset(%Camera{}, %{}).valid?

    camera =
      Repo.insert!(
        Camera.changeset(%Camera{}, %{id: "division-1", branch: "División", label: "Cámara 1"})
      )

    assert camera.id == "division-1"

    assert {:error, duplicate} =
             Repo.insert(
               Camera.changeset(%Camera{}, %{id: camera.id, branch: "Other", label: "Other"})
             )

    assert errors_on(duplicate).id == ["has already been taken"]
  end

  test "camera colors are limited to the named palette" do
    changeset =
      Camera.changeset(%Camera{}, %{
        id: "division-2",
        branch: "División",
        label: "Cámara 2",
        color: "ultraviolet"
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :color)
  end

  test "camera metadata and sources save atomically and empty edits preserve sources" do
    attrs = %{id: "division-3", branch: "División", label: "Tres", color: "teal"}

    assert {:ok, camera} =
             Monitoring.save_camera(attrs, %{
               "principal" => "rtsp://user:secret@example.test/main",
               "secundaria" => "rtsp://example.test/sub"
             })

    assert {:ok, _updated} =
             Monitoring.save_camera(%{attrs | label: "Tres editada"}, %{
               "principal" => "",
               "secundaria" => nil
             })

    assert {:ok, "rtsp://user:secret@example.test/main"} =
             Monitoring.source_url(camera.id, "principal")

    assert Repo.get!(Camera, camera.id).label == "Tres editada"
  end

  test "catalog writes never log RTSP credentials" do
    logs =
      capture_log(fn ->
        assert {:ok, _camera} =
                 Monitoring.save_camera(
                   %{id: "division-2", branch: "División", label: "Dos"},
                   %{"principal" => "rtsp://user:secret@example.test/main"}
                 )
      end)

    refute logs =~ "secret"
    refute logs =~ "example.test"
    refute logs =~ "rtsp://"
  end

  test "archive disables counting and restore preserves historical camera identity" do
    camera = Repo.insert!(%Camera{id: "division-4", branch: "División", label: "Cuatro"})

    assert {:ok, event, :inserted} =
             Sentinel.VisitorCounting.create_event(%{
               camera_id: camera.id,
               rule_revision: 1,
               crossed_at: ~U[2026-11-19 12:00:00.000000Z],
               direction: "entry",
               tracking_session_id: "archive-test",
               track_id: 1,
               crossing_number: 1,
               confidence: 0.9,
               bbox: %{},
               snapshot_key: "archive-snapshot",
               dedupe_key: "archive-event"
             })

    assert {:ok, _} = Monitoring.archive_camera(camera.id)
    assert {:ok, %{id: "division-4"}} = Monitoring.fetch_camera(camera.id)
    assert {:error, :unknown_camera} = Monitoring.validate_selection(camera.id, "principal")
    assert Repo.get!(Camera, camera.id).archived_at
    assert Repo.get!(Sentinel.VisitorCounting.PassageEvent, event.id)
    assert {:ok, _} = Monitoring.restore_camera(camera.id)
    assert :ok = Monitoring.validate_selection(camera.id, "principal")
  end

  test "sources validate URLs, redact inspection and translate unique/FK errors" do
    camera = Repo.insert!(%Camera{id: "division-1", branch: "División", label: "Cámara 1"})
    source = %CameraSource{camera_id: camera.id}

    for url <- ["", "file:///etc/passwd", "http://example.test", "rtsp:///missing-host"] do
      refute CameraSource.changeset(source, %{quality: "principal", url: url}).valid?
    end

    attrs = %{quality: "principal", url: "rtsp://user:secret@example.test/private"}
    inserted = Repo.insert!(CameraSource.changeset(source, attrs), log: false)
    refute inspect(inserted) =~ "secret"
    assert {:error, duplicate} = Repo.insert(CameraSource.changeset(source, attrs), log: false)
    assert errors_on(duplicate).camera_id == ["has already been taken"]

    assert {:error, missing} =
             Repo.insert(CameraSource.changeset(%CameraSource{camera_id: "missing"}, attrs),
               log: false
             )

    assert errors_on(missing).camera_id == ["does not exist"]
    assert Repo.preload(camera, :sources).sources |> length() == 1
  end
end

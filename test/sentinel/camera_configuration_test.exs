defmodule Sentinel.CameraConfigurationTest do
  use Sentinel.DataCase, async: true
  alias Sentinel.Monitoring.{Camera, CameraSource}

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

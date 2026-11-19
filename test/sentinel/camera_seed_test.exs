defmodule Sentinel.CameraSeedTest do
  use Sentinel.DataCase, async: false
  import ExUnit.CaptureLog
  alias Sentinel.Monitoring
  alias Sentinel.Monitoring.{Camera, CameraSource, SeedImporter}

  setup do
    path = Path.join(System.tmp_dir!(), "camera-seed-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)

    sources =
      Map.new(SeedImporter.catalog(), fn camera ->
        {camera.id,
         %{
           "principal" => "rtsp://user:secret@example.test/main",
           "secundaria" => "rtsp://user:secret@example.test/sub"
         }}
      end)

    %{path: path, sources: sources}
  end

  test "private import is atomic, idempotent and updates only declared fields", %{
    path: path,
    sources: sources
  } do
    Repo.insert!(%Camera{id: "extra", branch: "Other", label: "Unrelated"})
    File.write!(path, Jason.encode!(sources))
    assert {:ok, %{cameras: 8, sources: 16}} = SeedImporter.import_file(path)
    original = Repo.get!(Camera, "division-1")
    connection = Repo.get_by!(CameraSource, camera_id: original.id, quality: "principal")
    Repo.update!(Ecto.Changeset.change(original, label: "Edited"))
    changed = put_in(sources, ["division-1", "principal"], "rtsp://example.test/changed")
    File.write!(path, Jason.encode!(changed))
    assert {:ok, %{sources: 16}} = SeedImporter.import_file(path)
    assert Repo.aggregate(Camera, :count) == 9
    assert Repo.aggregate(CameraSource, :count) == 16
    assert Repo.get!(Camera, "extra").label == "Unrelated"
    assert Repo.get!(Camera, original.id).inserted_at == original.inserted_at
    assert Repo.get!(Camera, original.id).label == "Cámara 1"
    next = Repo.get!(CameraSource, connection.id)
    assert next.inserted_at == connection.inserted_at
    assert next.url == "rtsp://example.test/changed"
    assert {:ok, "rtsp://example.test/changed"} = Monitoring.source_url(original.id, "principal")

    assert {:ok, "rtsp://user:secret@example.test/sub"} =
             Monitoring.source_url(original.id, "secundaria")

    assert Enum.all?(
             Monitoring.list_cameras(),
             &(Map.keys(&1) |> Enum.sort() == [:branch, :id, :label])
           )
  end

  test "seeding and reads do not log private endpoints", %{path: path, sources: sources} do
    File.write!(path, Jason.encode!(sources))

    logs =
      capture_log([level: :debug], fn ->
        assert {:ok, _} = SeedImporter.import_file(path)
        assert {:ok, _} = Monitoring.source_url("division-1", "principal")
        assert {:ok, _} = SeedImporter.import_file(path)
      end)

    refute logs =~ "secret"
    refute logs =~ "example.test"
    refute logs =~ "rtsp://user"
  end

  test "invalid input fails without partial writes or source/path disclosure", %{
    path: path,
    sources: sources
  } do
    assert {:error, message} = SeedImporter.import_file(nil)
    assert message =~ "Set CAMERA_RTSP_SOURCES_FILE"
    assert {:error, _} = SeedImporter.import_file(path)

    for content <- [
          "not json rtsp://secret/private",
          "[]",
          "null",
          Jason.encode!(%{}),
          Jason.encode!(put_in(sources, ["division-1", "principal"], "http://secret/private")),
          Jason.encode!(
            Map.put(sources, "lavirgen-4", %{"principal" => "rtsp://secret/private"})
          ),
          Jason.encode!(Map.put(sources, "division-1", "rtsp://secret/private"))
        ] do
      File.write!(path, content)
      assert {:error, error} = SeedImporter.import_file(path)
      refute error =~ "secret"
      refute error =~ path
      assert Repo.aggregate(Camera, :count) == 0
      assert Repo.aggregate(CameraSource, :count) == 0
    end
  end
end

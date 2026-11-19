defmodule Sentinel.MonitoringFixtures do
  @moduledoc false
  alias Sentinel.Monitoring.{Camera, CameraSource, SeedImporter}
  alias Sentinel.Repo

  def camera_catalog_fixture do
    for attrs <- SeedImporter.catalog() do
      Repo.insert!(Camera.changeset(%Camera{}, attrs))
    end

    :ok
  end

  def camera_source_fixture(camera_id, quality, url) do
    %CameraSource{camera_id: camera_id}
    |> CameraSource.changeset(%{quality: quality, url: url})
    |> Repo.insert!(log: false)
  end
end

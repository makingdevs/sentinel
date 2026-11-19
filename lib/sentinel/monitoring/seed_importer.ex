defmodule Sentinel.Monitoring.SeedImporter do
  @moduledoc "Imports the private bootstrap file; never used during application startup."
  alias Sentinel.Monitoring.{Camera, CameraSource}
  alias Sentinel.Repo

  @qualities ~w(principal secundaria)

  def catalog do
    for {prefix, branch} <- [{"division", "División"}, {"lavirgen", "La Virgen"}], n <- 1..4 do
      %{id: "#{prefix}-#{n}", branch: branch, label: "Cámara #{n}"}
    end
  end

  def import_file(path) do
    with {:ok, sources} <- read_sources(path),
         {:ok, rows} <- validate_sources(sources) do
      persist(rows)
    end
  end

  defp read_sources(path) when is_binary(path) and path != "" do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, sources} when is_map(sources) -> {:ok, sources}
          _ -> {:error, "CAMERA_RTSP_SOURCES_FILE must contain a JSON object"}
        end

      {:error, reason} ->
        {:error,
         "Cannot read CAMERA_RTSP_SOURCES_FILE (#{reason}); provide a readable private JSON file"}
    end
  end

  defp read_sources(_path),
    do: {:error, "Set CAMERA_RTSP_SOURCES_FILE to the private camera JSON file before seeding"}

  defp validate_sources(sources) do
    Enum.reduce_while(catalog(), {:ok, []}, fn camera, {:ok, rows} ->
      connections = Map.get(sources, camera.id)

      if is_map(connections) and
           Enum.all?(@qualities, &CameraSource.valid_url?(Map.get(connections, &1))) do
        {:cont, {:ok, [{camera, connections} | rows]}}
      else
        {:halt,
         {:error, "Camera #{camera.id} needs principal and secundaria RTSP URLs with a host"}}
      end
    end)
  end

  defp persist(rows) do
    case Repo.transaction(
           fn ->
             for {camera, connections} <- rows do
               Repo.insert!(Camera.changeset(%Camera{}, camera),
                 conflict_target: [:id],
                 on_conflict: {:replace, [:branch, :label, :updated_at]},
                 log: false
               )

               for quality <- @qualities do
                 %CameraSource{camera_id: camera.id}
                 |> CameraSource.changeset(%{
                   quality: quality,
                   url: Map.fetch!(connections, quality)
                 })
                 |> Repo.insert!(
                   conflict_target: [:camera_id, :quality],
                   on_conflict: {:replace, [:url, :updated_at]},
                   log: false
                 )
               end
             end

             %{cameras: length(rows), sources: length(rows) * 2}
           end,
           log: false
         ) do
      {:ok, counts} ->
        {:ok, counts}

      {:error, _} ->
        {:error, "Camera seed transaction failed; check database availability and migrations"}
    end
  rescue
    _ in [
      Postgrex.Error,
      DBConnection.ConnectionError,
      Ecto.InvalidChangesetError,
      Ecto.ConstraintError
    ] ->
      {:error, "Camera seed failed; check database availability, migrations and input"}
  end
end

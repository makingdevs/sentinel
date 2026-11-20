defmodule Sentinel.Monitoring do
  @moduledoc "Public catalog and same-origin HLS URLs. RTSP sources remain server-side."

  import Ecto.Query

  alias Sentinel.Monitoring.{Camera, CameraSource, Stream}
  alias Sentinel.Repo

  @qualities ~w(secundaria principal)

  def config, do: Application.fetch_env!(:sentinel, :monitoring)

  def admin_cameras do
    cameras = Repo.all(from c in Camera, order_by: c.id)
    ids = Enum.map(cameras, & &1.id)

    sources =
      Repo.all(
        from s in CameraSource, where: s.camera_id in ^ids, select: {s.camera_id, s.quality}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    rules =
      Repo.all(
        from r in Sentinel.VisitorCounting.Rule,
          where: r.camera_id in ^ids,
          select: {r.camera_id, r.enabled}
      )
      |> Map.new()

    captures =
      Repo.all(
        from e in Sentinel.VisitorCounting.PassageEvent,
          where: e.camera_id in ^ids,
          group_by: e.camera_id,
          select: {e.camera_id, max(coalesce(e.snapshot_received_at, e.crossed_at))}
      )
      |> Map.new(fn
        {id, %NaiveDateTime{} = value} -> {id, DateTime.from_naive!(value, "Etc/UTC")}
        {id, value} -> {id, value}
      end)

    Enum.map(cameras, fn camera ->
      enabled = Map.get(rules, camera.id, false)

      %{
        camera: camera,
        sources: Map.get(sources, camera.id, []),
        counting_enabled: enabled,
        counting_status: Sentinel.VisitorCounting.Manager.status(camera.id),
        last_capture: Map.get(captures, camera.id)
      }
    end)
  end

  def get_camera(id) when is_binary(id), do: Repo.get(Camera, id)

  def save_camera(attrs, source_attrs \\ %{}) do
    id = attrs["id"] || attrs[:id]
    camera = if is_binary(id), do: Repo.get(Camera, id), else: nil
    changeset = Camera.changeset(camera || %Camera{}, attrs)

    result =
      Repo.transaction(fn ->
        camera =
          case Repo.insert_or_update(changeset, log: false) do
            {:ok, camera} -> camera
            {:error, changeset} -> Repo.rollback(changeset)
          end

        changed_qualities =
          for {quality, url} <- source_attrs, url not in [nil, ""], reduce: [] do
            changed ->
              source =
                Repo.get_by(CameraSource, camera_id: camera.id, quality: quality) ||
                  %CameraSource{camera_id: camera.id}

              source_changeset = CameraSource.changeset(source, %{quality: quality, url: url})

              case Repo.insert_or_update(source_changeset, log: false) do
                {:ok, _source} ->
                  if Ecto.Changeset.changed?(source_changeset, :url),
                    do: [quality | changed],
                    else: changed

                {:error, changeset} ->
                  Repo.rollback(changeset)
              end
          end

        {camera, changed_qualities}
      end)

    case result do
      {:ok, {camera, changed_qualities}} ->
        Enum.each(changed_qualities, &stop_streams(id, &1))

        if changed_qualities != [] do
          Phoenix.PubSub.broadcast(
            Sentinel.PubSub,
            "visitor_rules",
            {:camera_sources_changed, id}
          )
        end

        notify_camera({:ok, camera}, id)

      {:error, _} = error ->
        error
    end
  end

  def archive_camera(id) do
    result =
      Repo.transaction(fn ->
        camera = Repo.get!(Camera, id)
        Repo.update!(Ecto.Changeset.change(camera, archived_at: DateTime.utc_now()))

        case disable_rule(id) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback(changeset)
        end

        :ok
      end)

    if match?({:ok, _}, result), do: stop_streams(id)
    notify_camera(result, id)
  end

  defp disable_rule(id) do
    case Repo.get_by(Sentinel.VisitorCounting.Rule, camera_id: id) do
      nil -> {:ok, nil}
      rule -> Repo.update(Sentinel.VisitorCounting.Rule.changeset(rule, %{enabled: false}))
    end
  end

  def restore_camera(id) do
    result =
      Repo.transaction(fn ->
        camera = Repo.get!(Camera, id)
        Repo.update!(Ecto.Changeset.change(camera, archived_at: nil))
        :ok
      end)

    notify_camera(result, id)
  end

  defp notify_camera({:ok, _} = result, id) do
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "camera_catalog", {:camera_changed, id})
    result
  end

  defp notify_camera(result, _id), do: result

  defp stop_streams(camera_id, quality \\ nil) do
    for {{^camera_id, stream_quality}, pid} <-
          Registry.select(Sentinel.Monitoring.Registry, [
            {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
          ]),
        is_nil(quality) or quality == stream_quality do
      DynamicSupervisor.terminate_child(Sentinel.Monitoring.Supervisor, pid)
    end

    for {{^camera_id, stream_quality, _engine}, pid} <-
          Registry.select(Sentinel.Monitoring.Registry, [
            {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
          ]),
        is_nil(quality) or quality == stream_quality do
      DynamicSupervisor.terminate_child(Sentinel.Monitoring.Supervisor, pid)
    end
  end

  def list_cameras do
    Repo.all(
      from c in Camera,
        where: is_nil(c.archived_at),
        order_by: c.id,
        select: %{id: c.id, branch: c.branch, label: c.label, color: c.color}
    )
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> []
  end

  def camera_options do
    list_cameras()
    |> Enum.group_by(& &1.branch, &{&1.label, &1.id})
    |> Enum.sort_by(&elem(&1, 0))
  end

  def fetch_camera(id) when is_binary(id) do
    case Repo.one(
           from c in Camera,
             where: c.id == ^id,
             select: %{id: c.id, branch: c.branch, label: c.label, color: c.color}
         ) do
      nil -> {:error, :unknown_camera}
      camera -> {:ok, camera}
    end
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, :catalog_unavailable}
  end

  def fetch_camera(_id), do: {:error, :unknown_camera}

  def validate_selection(id, quality) do
    with {:ok, _camera} <- fetch_camera(id),
         false <- archived?(id) do
      if quality in @qualities, do: :ok, else: {:error, :unknown_quality}
    else
      true -> {:error, :unknown_camera}
      error -> error
    end
  end

  defp archived?(id),
    do: Repo.exists?(from c in Camera, where: c.id == ^id and not is_nil(c.archived_at))

  def player_url(id, quality) do
    with :ok <- validate_selection(id, quality) do
      {:ok, "/hls/#{id}/#{quality}/index.m3u8"}
    end
  end

  def player_url(id, quality, "off"), do: player_url(id, quality)

  def player_url(id, quality, engine) do
    with :ok <- validate_selection(id, quality),
         :ok <- Sentinel.Detection.validate_engine(engine),
         true <- Sentinel.Detection.available?(engine) do
      {:ok, "/hls/#{id}/#{quality}/#{engine}/index.m3u8"}
    else
      false -> {:error, :detector_unavailable}
      error -> error
    end
  end

  def retry_detector(id, quality, engine) do
    case Registry.lookup(Sentinel.Monitoring.Registry, stream_key(id, quality, engine)) do
      [{pid, _}] -> GenServer.cast(pid, :retry_detector)
      [] -> :ok
    end
  end

  def detection_status(id, quality, engine) do
    with :ok <- validate_selection(id, quality),
         true <- Sentinel.Detection.valid_engine?(engine) do
      case Registry.lookup(Sentinel.Monitoring.Registry, stream_key(id, quality, engine)) do
        [{pid, _}] -> GenServer.call(pid, :status)
        [] -> :loading
      end
    else
      _ -> :error
    end
  catch
    :exit, _ -> :error
  end

  def source_url(id, quality) do
    with :ok <- validate_selection(id, quality) do
      source =
        Repo.one(
          from(s in CameraSource,
            where: s.camera_id == ^id and s.quality == ^quality,
            select: s.url,
            limit: 1
          ),
          log: false
        )

      cond do
        is_nil(source) -> {:error, :source_not_configured}
        CameraSource.valid_url?(source) -> {:ok, source}
        true -> {:error, :invalid_source}
      end
    end
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, :source_unavailable}
  end

  def media_file(id, quality, filename), do: media_file(id, quality, filename, "off")

  def media_file(id, quality, filename, engine) do
    with :ok <- validate_selection(id, quality),
         :ok <- Sentinel.Detection.validate_engine(engine),
         true <- Sentinel.Detection.available?(engine),
         :ok <- validate_filename(filename),
         {:ok, url} <- source_url(id, quality),
         {:ok, pid} <- ensure_stream(id, quality, url, engine) do
      Stream.file(pid, filename)
    else
      false -> {:error, :detector_unavailable}
      error -> error
    end
  end

  defp ensure_stream(id, quality, url, engine) do
    key = stream_key(id, quality, engine)

    case Registry.lookup(Sentinel.Monitoring.Registry, key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               Sentinel.Monitoring.Supervisor,
               {Stream,
                key: key,
                source_url: url,
                pipeline_module:
                  Keyword.get(config(), :pipeline_module, Sentinel.Monitoring.Pipeline)}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _reason} -> {:error, :stream_unavailable}
        end
    end
  end

  defp stream_key(id, quality, "off"), do: {id, quality}
  defp stream_key(id, quality, engine), do: {id, quality, engine}

  defp validate_filename(filename) when is_binary(filename) do
    if Regex.match?(~r/\A[a-zA-Z0-9_-]+\.(m3u8|m4s|mp4)\z/, filename),
      do: :ok,
      else: {:error, :invalid_filename}
  end

  defp validate_filename(_filename), do: {:error, :invalid_filename}
end

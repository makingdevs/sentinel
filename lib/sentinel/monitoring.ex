defmodule Sentinel.Monitoring do
  @moduledoc "Public catalog and same-origin HLS URLs. RTSP sources remain server-side."

  alias Sentinel.Monitoring.Stream

  @qualities ~w(secundaria principal)

  def config, do: Application.fetch_env!(:sentinel, :monitoring)
  def list_cameras, do: Keyword.fetch!(config(), :cameras)

  def camera_options do
    list_cameras()
    |> Enum.group_by(& &1.branch, &{&1.label, &1.id})
    |> Enum.sort_by(&elem(&1, 0))
  end

  def fetch_camera(id) when is_binary(id) do
    case Enum.find(list_cameras(), &(&1.id == id)) do
      nil -> {:error, :unknown_camera}
      camera -> {:ok, camera}
    end
  end

  def fetch_camera(_id), do: {:error, :unknown_camera}

  def validate_selection(id, quality) do
    with {:ok, _camera} <- fetch_camera(id) do
      if quality in @qualities, do: :ok, else: {:error, :unknown_quality}
    end
  end

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
      sources = Keyword.get(config(), :sources, %{})

      source =
        case sources do
          %{^id => %{^quality => url}} -> url
          _ -> nil
        end

      case source do
        url when is_binary(url) ->
          case URI.new(url) do
            {:ok, %URI{scheme: "rtsp", host: host}} when is_binary(host) and host != "" ->
              {:ok, url}

            _ ->
              {:error, :invalid_source}
          end

        _ ->
          {:error, :source_not_configured}
      end
    end
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

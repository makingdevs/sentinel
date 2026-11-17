defmodule SentinelWeb.HlsController do
  use SentinelWeb, :controller

  alias Sentinel.Monitoring

  def show(conn, %{"camera_id" => id, "quality" => quality, "filename" => filename}) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    case Monitoring.media_file(id, quality, filename) do
      {:ok, body} ->
        conn |> put_resp_content_type(content_type(filename)) |> send_resp(200, body)

      {:error, reason}
      when reason in [:unknown_camera, :unknown_quality, :invalid_filename, :enoent] ->
        send_resp(conn, 404, "Recurso no disponible")

      {:error, _reason} ->
        conn
        |> put_resp_header("retry-after", "3")
        |> send_resp(503, "Video no disponible. Reintenta en unos segundos.")
    end
  end

  defp content_type(filename) do
    case Path.extname(filename) do
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".m4s" -> "video/iso.segment"
      ".mp4" -> "video/mp4"
    end
  end
end

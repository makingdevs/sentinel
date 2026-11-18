defmodule SentinelWeb.VisitorSnapshotController do
  use SentinelWeb, :controller
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.Snapshots

  def show(conn, %{"event_id" => id}) do
    with %{snapshot_key: key} <- VisitorCounting.get_event(id),
         {:ok, path} <- Snapshots.path(key),
         {:ok, %{type: :regular}} <- File.lstat(path) do
      conn
      |> put_resp_content_type("image/jpeg")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Capture not found")
    end
  end
end

defmodule SentinelWeb.VisitorAccess do
  @moduledoc "Loopback-only visitor history/configuration, checked for HTTP and connected LiveViews."
  import Plug.Conn, except: [assign: 3]
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def init(opts), do: opts

  def call(conn, _opts) do
    if allowed?(conn.remote_ip),
      do: conn,
      else: conn |> send_resp(403, "Visitor history is restricted to localhost") |> halt()
  end

  def allowed?({127, _, _, _}), do: true
  def allowed?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def allowed?(_), do: false

  def socket_allowed?(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: ip} -> allowed?(ip)
      _ -> false
    end
  end

  def on_mount(:local, _params, _session, socket) do
    if socket_allowed?(socket),
      do: {:cont, assign(socket, :visitor_access?, true)},
      else: {:halt, redirect(socket, to: "/cameras")}
  end
end

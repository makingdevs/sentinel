defmodule SentinelWeb.VisitorAccess do
  @moduledoc "Loopback-only visitor history/configuration, checked for HTTP and connected LiveViews."
  import Plug.Conn, except: [assign: 3]
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def init(opts), do: opts

  def call(conn, _opts) do
    case allowed?(conn.remote_ip) do
      true -> conn
      false -> conn |> send_resp(403, "Visitor history is restricted to localhost") |> halt()
    end
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
    case socket_allowed?(socket) do
      true -> {:cont, assign(socket, :visitor_access?, true)}
      false -> {:halt, redirect(socket, to: "/cameras")}
    end
  end
end

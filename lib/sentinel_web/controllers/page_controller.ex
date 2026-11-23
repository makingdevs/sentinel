defmodule SentinelWeb.PageController do
  use SentinelWeb, :controller

  def home(conn, _params) do
    render(conn, :home, visitor_access?: SentinelWeb.VisitorAccess.allowed?(conn.remote_ip))
  end
end

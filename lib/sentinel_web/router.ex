defmodule SentinelWeb.Router do
  use SentinelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SentinelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :visitor_local do
    plug SentinelWeb.VisitorAccess
  end

  scope "/", SentinelWeb do
    pipe_through [:browser, :visitor_local]

    get "/visitors/events/:event_id/snapshot", VisitorSnapshotController, :show

    live_session :visitor_local, on_mount: [{SentinelWeb.VisitorAccess, :local}] do
      live "/cameras/catalog", CameraCatalogLive, :index
      live "/visitors", VisitorCountingLive, :index
      live "/visitors/events/:event_id", VisitorCountingLive, :show
    end
  end

  scope "/", SentinelWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/cameras", CameraLive, :index
  end

  # Same-origin HLS resources; they are binary media, not browser HTML.
  scope "/hls", SentinelWeb do
    get "/:camera_id/:quality/:engine/status", HlsController, :status
    get "/:camera_id/:quality/:engine/:filename", HlsController, :show
    get "/:camera_id/:quality/:filename", HlsController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", SentinelWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  case Application.compile_env(:sentinel, :dev_routes) do
    enabled when enabled not in [false, nil] ->
      # If you want to use the LiveDashboard in production, you should put
      # it behind authentication and allow only admins to access it.
      # If your application does not have an admins-only section yet,
      # you can use Plug.BasicAuth to set up some basic authentication
      # as long as you are also using SSL (which you should anyway).
      import Phoenix.LiveDashboard.Router

      scope "/dev" do
        pipe_through :browser

        live_dashboard "/dashboard", metrics: SentinelWeb.Telemetry
        forward "/mailbox", Plug.Swoosh.MailboxPreview
      end

    _ ->
      :ok
  end
end

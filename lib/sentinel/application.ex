defmodule Sentinel.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Membrane debug/crash messages can include RTSP options. Redact origins
    # before any logger handler receives them.
    :logger.add_primary_filter(:sentinel_rtsp, {&Sentinel.Monitoring.LogFilter.filter/2, []})

    children = [
      SentinelWeb.Telemetry,
      Sentinel.Repo,
      {DNSCluster, query: Application.get_env(:sentinel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sentinel.PubSub},
      {Registry, keys: :unique, name: Sentinel.Monitoring.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Sentinel.Monitoring.Supervisor},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Sentinel.Detection.Supervisor, max_children: 8},
      Sentinel.VisitorCounting.Supervisor,
      # Start to serve requests, typically the last entry
      SentinelWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sentinel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SentinelWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

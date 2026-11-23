defmodule Sentinel.VisitorCounting.Supervisor do
  @moduledoc false
  use Supervisor
  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Sentinel.VisitorCounting.Registry},
      {Registry, keys: :unique, name: Sentinel.VisitorCounting.SnapshotRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: Sentinel.VisitorCounting.SnapshotSources},
      Sentinel.VisitorCounting.Writer,
      {DynamicSupervisor, strategy: :one_for_one, name: Sentinel.VisitorCounting.Cameras}
    ]

    children =
      cond do
        Sentinel.VisitorCounting.config(:start_manager, true) ->
          children ++ [Sentinel.VisitorCounting.Manager, Sentinel.VisitorCounting.Retention]

        true ->
          children
      end

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

defmodule Sentinel.TestMediaPipeline do
  @behaviour Sentinel.Monitoring.Pipeline

  @impl true
  def start(options) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Sentinel.TestMediaSupervisor,
        {Sentinel.TestMediaProcess, options}
      )

    {:ok, pid, pid}
  end

  @impl true
  def stop(pid), do: GenServer.stop(pid, :normal)
end

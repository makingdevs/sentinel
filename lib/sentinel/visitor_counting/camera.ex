defmodule Sentinel.VisitorCounting.Camera do
  @moduledoc "Canonical analytics lifetime, reconnect backoff and progress watchdog for one camera."
  use GenServer, restart: :temporary
  alias Sentinel.VisitorCounting

  def start_link(opts) do
    rule = Keyword.fetch!(opts, :rule)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Sentinel.VisitorCounting.Registry, rule.camera_id}}
    )
  end

  def status(pid) do
    GenServer.call(pid, :status, 1_000)
  catch
    :exit, {reason, {GenServer, :call, _}}
    when reason in [:timeout, :noproc, :normal, :shutdown] ->
      :error
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      rule: Keyword.fetch!(opts, :rule),
      status: :loading,
      runner: VisitorCounting.config(:pipeline_module, Sentinel.VisitorCounting.Pipeline),
      pipeline: nil,
      monitor: nil,
      attempt: 0,
      timer: nil,
      session: nil,
      last_progress: now(),
      metrics: %{frames: 0, crossings: 0}
    }

    if VisitorCounting.config(:primary_snapshots, false) and
         (VisitorCounting.config(:primary_snapshot_cameras, :all) == :all or
            state.rule.camera_id in VisitorCounting.config(:primary_snapshot_cameras, [])) do
      send(self(), :start_snapshot_source)
    end

    Process.send_after(self(), :watchdog, 5_000)
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl true
  def handle_call(:status, _from, state) do
    stats = Sentinel.VisitorCounting.Writer.stats(state.rule.camera_id)
    saturated? = stats.capacity > 0 and stats.queued >= stats.capacity
    {:reply, if(saturated?, do: :saturated, else: state.status), state}
  end

  @impl true
  def handle_info(:start_snapshot_source, state) do
    case DynamicSupervisor.start_child(
           Sentinel.VisitorCounting.SnapshotSources,
           {Sentinel.VisitorCounting.SnapshotSource,
            owner: self(), camera_id: state.rule.camera_id}
         ) do
      {:ok, _pid} -> :ok
      {:error, _reason} -> Process.send_after(self(), :start_snapshot_source, 1_000)
    end

    {:noreply, state}
  end

  def handle_info({:connect, token}, %{timer: token} = state),
    do: {:noreply, connect(%{state | timer: nil})}

  def handle_info({:analytics_status, pid, status}, %{pipeline: pid} = state) do
    if status == :error do
      {:noreply, disconnect(state)}
    else
      {:noreply,
       publish(%{state | attempt: if(status == :active, do: 0, else: state.attempt)}, status)}
    end
  end

  def handle_info({:analytics_progress, pid, crossings}, %{pipeline: pid} = state) do
    metrics = %{frames: state.metrics.frames + 1, crossings: state.metrics.crossings + crossings}
    {:noreply, %{state | last_progress: now(), metrics: metrics}}
  end

  def handle_info({:analytics_error, pid, _reason}, %{pipeline: pid} = state),
    do: {:noreply, disconnect(state)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor: ref} = state),
    do: {:noreply, retry(%{state | pipeline: nil, monitor: nil})}

  def handle_info(:watchdog, state) do
    Process.send_after(self(), :watchdog, 5_000)
    timeout = if state.status == :loading, do: 130_000, else: 30_000

    state =
      if state.pipeline != nil and now() - state.last_progress > timeout,
        do: disconnect(state),
        else: state

    {:noreply, state}
  end

  def handle_info(_stale, state), do: {:noreply, state}

  defp connect(%{pipeline: pid} = state) when is_pid(pid), do: state

  defp connect(state) do
    with {:ok, url} <- Sentinel.Monitoring.source_url(state.rule.camera_id, "secundaria"),
         session = Ecto.UUID.generate(),
         {:ok, _supervisor, pipeline} <-
           state.runner.start(%{
             owner: self(),
             source_url: url,
             rule: state.rule,
             session: session
           }) do
      publish(
        %{
          state
          | pipeline: pipeline,
            monitor: Process.monitor(pipeline),
            session: session,
            last_progress: now()
        },
        :loading
      )
    else
      _ -> retry(state)
    end
  end

  defp disconnect(state) do
    if state.monitor, do: Process.demonitor(state.monitor, [:flush])
    if state.pipeline, do: stop_pipeline(state)
    retry(%{state | pipeline: nil, monitor: nil})
  end

  defp retry(%{timer: token} = state) when not is_nil(token), do: state

  defp retry(state) do
    token = make_ref()

    delay =
      min(
        30_000,
        VisitorCounting.config(:reconnect_ms, 1_000) * Integer.pow(2, min(state.attempt, 5))
      )

    Process.send_after(self(), {:connect, token}, delay)
    publish(%{state | timer: token, attempt: state.attempt + 1}, :error)
  end

  defp publish(state, status) do
    if state.status != status do
      Phoenix.PubSub.broadcast(
        Sentinel.PubSub,
        "visitor_status",
        {:visitor_status, state.rule.camera_id, status}
      )
    end

    %{state | status: status}
  end

  @impl true
  def terminate(_reason, state) do
    if state.pipeline, do: stop_pipeline(state)
    :ok
  end

  defp stop_pipeline(state) do
    state.runner.stop(state.pipeline)
  catch
    :exit, {reason, _} when reason in [:noproc, :normal, :shutdown, :timeout] -> :ok
  end

  defp now, do: System.monotonic_time(:millisecond)
end

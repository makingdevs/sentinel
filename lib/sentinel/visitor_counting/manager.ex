defmodule Sentinel.VisitorCounting.Manager do
  @moduledoc "Owns a single analytics process per enabled rule, independently of HLS viewers."
  use GenServer
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.Camera

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def sync, do: GenServer.call(__MODULE__, :sync)

  def status(camera_id) do
    case Process.whereis(__MODULE__) do
      nil -> :disabled
      _ -> GenServer.call(__MODULE__, {:status, camera_id})
    end
  catch
    :exit, {reason, {GenServer, :call, _}}
    when reason in [:timeout, :noproc, :normal, :shutdown] ->
      :error
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    # A manager crash can leave children in the preceding DynamicSupervisor.
    # Restart their sessions rather than adopt an unknown/stale rule revision.
    for {_, pid, _, _} <- DynamicSupervisor.which_children(Sentinel.VisitorCounting.Cameras),
        do: DynamicSupervisor.terminate_child(Sentinel.VisitorCounting.Cameras, pid)

    Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_rules")
    send(self(), :sync)

    {:ok,
     %{
       children: %{},
       capacity: MapSet.new(),
       max: Keyword.get(opts, :max_cameras, VisitorCounting.config(:max_cameras, 2))
     }}
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, reconcile(state)}

  def handle_call({:status, id}, _from, state) do
    status =
      case Map.get(state.children, id) do
        nil -> if MapSet.member?(state.capacity, id), do: :capacity, else: :disabled
        %{pid: pid} -> Camera.status(pid)
      end

    {:reply, status, state}
  end

  @impl true
  def handle_info(:sync, state) do
    Process.send_after(self(), :sync, 5_000)
    {:noreply, reconcile(state)}
  end

  def handle_info({:rule_changed, _id}, state), do: {:noreply, reconcile(state)}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    children = Map.reject(state.children, fn {_id, child} -> child.pid == pid end)
    {:noreply, reconcile(%{state | children: children})}
  end

  defp reconcile(state) do
    rules = VisitorCounting.enabled_rules()
    wanted = Map.new(rules, &{&1.camera_id, &1})

    children =
      Enum.reduce(state.children, state.children, fn {id, child}, children ->
        if not Map.has_key?(wanted, id) or wanted[id].revision != child.revision do
          Process.demonitor(child.ref, [:flush])
          DynamicSupervisor.terminate_child(Sentinel.VisitorCounting.Cameras, child.pid)
          Map.delete(children, id)
        else
          children
        end
      end)

    {children, capacity} =
      Enum.reduce(rules, {children, MapSet.new()}, fn rule, {children, capacity} ->
        cond do
          Map.has_key?(children, rule.camera_id) ->
            {children, capacity}

          map_size(children) >= state.max ->
            {children, MapSet.put(capacity, rule.camera_id)}

          true ->
            case DynamicSupervisor.start_child(
                   Sentinel.VisitorCounting.Cameras,
                   {Camera, rule: rule}
                 ) do
              {:ok, pid} ->
                {Map.put(children, rule.camera_id, %{
                   pid: pid,
                   revision: rule.revision,
                   ref: Process.monitor(pid)
                 }), capacity}

              {:error, {:already_started, pid}} ->
                {Map.put(children, rule.camera_id, %{
                   pid: pid,
                   revision: rule.revision,
                   ref: Process.monitor(pid)
                 }), capacity}

              {:error, _} ->
                {children, MapSet.put(capacity, rule.camera_id)}
            end
        end
      end)

    %{state | children: children, capacity: capacity}
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> state
  end

  @impl true
  def terminate(_reason, state) do
    for {_id, child} <- state.children,
        do: DynamicSupervisor.terminate_child(Sentinel.VisitorCounting.Cameras, child.pid)

    :ok
  end
end

defmodule Sentinel.VisitorCounting.SnapshotSource do
  @moduledoc "Owner-bound primary acquisition. Private ETS history supports nonblocking reads."
  use GenServer, restart: :transient
  alias Sentinel.VisitorCounting
  @registry Sentinel.VisitorCounting.SnapshotRegistry

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def generation(camera) do
    case read(camera) do
      {:ok, %{generation: generation}} -> generation
      _ -> nil
    end
  end

  def read(camera) do
    case Registry.lookup(@registry, camera) do
      [{_, table}] ->
        case :ets.lookup(table, :cache) do
          [{:cache, cache}] -> {:ok, cache}
          _ -> {:error, :missing}
        end

      [] ->
        {:error, :missing}
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  def format(source, generation), do: GenServer.call(source, {:format, generation}, 1_000)
  def put(source, generation, frame), do: GenServer.call(source, {:put, generation, frame}, 1_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)
    camera = Keyword.fetch!(opts, :camera_id)
    table = :ets.new(__MODULE__, [:set, :protected, read_concurrency: true])
    {:ok, _} = Registry.register(@registry, camera, table)

    state = %{
      owner: owner,
      owner_ref: Process.monitor(owner),
      camera: camera,
      table: table,
      runner:
        Keyword.get(
          opts,
          :runner,
          VisitorCounting.config(
            :snapshot_pipeline_module,
            Sentinel.VisitorCounting.SnapshotPipeline
          )
        ),
      pipeline: nil,
      monitor: nil,
      generation: make_ref(),
      connection: nil,
      attempt: 0,
      timer: nil,
      failure_reason: "unavailable",
      last_progress: System.monotonic_time(:millisecond)
    }

    clear(state, "missing")
    Process.send_after(self(), :sweep, 500)
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: {:noreply, connect(state)}

  @impl true
  def handle_call({:format, connection}, _from, %{connection: connection} = state) do
    state = %{state | generation: make_ref()}
    clear(state, "missing")
    {:reply, {:ok, state.generation}, state}
  end

  def handle_call({:put, generation, frame}, _from, %{generation: generation} = state) do
    [{:cache, cache}] = :ets.lookup(state.table, :cache)
    now = System.monotonic_time(:millisecond)

    cond do
      byte_size(frame.jpeg) > 2 * 1024 * 1024 ->
        clear(state, "oversized")
        {:reply, {:error, :oversized}, state}

      frame.width > 3840 or frame.height > 2160 or frame.width < 1 or frame.height < 1 ->
        clear(state, "oversized")
        {:reply, {:error, :oversized}, state}

      true ->
        frames =
          [Map.put(frame, :camera_id, state.camera) | cache.frames]
          |> Enum.filter(&(now - &1.received_mono <= 3_000))
          |> Enum.take(6)
          |> Enum.reduce({[], 0}, fn frame, {frames, bytes} ->
            cond do
              bytes + byte_size(frame.jpeg) <= 12 * 1024 * 1024 ->
                {frames ++ [frame], bytes + byte_size(frame.jpeg)}

              true ->
                {frames, bytes}
            end
          end)

        {frames, bytes} = frames

        :ets.insert(
          state.table,
          {:cache, %{generation: generation, frames: frames, bytes: bytes, reason: nil}}
        )

        {:reply, :ok, %{state | attempt: 0, last_progress: now, failure_reason: "unavailable"}}
    end
  end

  def handle_call(_, _from, state), do: {:reply, {:error, :generation_mismatch}, state}

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state),
    do: {:noreply, retry(%{state | pipeline: nil, monitor: nil})}

  def handle_info({:connect, token}, %{timer: token} = state),
    do: {:noreply, connect(%{state | timer: nil})}

  def handle_info({:snapshot_error, pid, :oversized}, %{pipeline: pid} = state) do
    clear(state, "oversized")
    {:noreply, %{state | failure_reason: "oversized"}}
  end

  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, 500)
    now = System.monotonic_time(:millisecond)
    [{:cache, cache}] = :ets.lookup(state.table, :cache)
    frames = Enum.filter(cache.frames, &(now - &1.received_mono <= 3_000))

    :ets.insert(
      state.table,
      {:cache,
       %{cache | frames: frames, bytes: Enum.reduce(frames, 0, &(byte_size(&1.jpeg) + &2))}}
    )

    state =
      cond do
        state.pipeline != nil and now - state.last_progress > 130_000 ->
          Process.demonitor(state.monitor, [:flush])
          state.runner.stop(state.pipeline)
          retry(%{state | pipeline: nil, monitor: nil})

        true ->
          state
      end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp connect(state) do
    generation = make_ref()

    state = %{
      state
      | generation: generation,
        connection: generation,
        last_progress: System.monotonic_time(:millisecond),
        failure_reason: "unavailable"
    }

    clear(state, "unavailable")

    with {:ok, url} <- Sentinel.Monitoring.source_url(state.camera, "principal"),
         {:ok, _, pid} <-
           state.runner.start(%{
             owner: self(),
             source: self(),
             camera_id: state.camera,
             source_url: url,
             generation: generation
           }) do
      %{state | pipeline: pid, monitor: Process.monitor(pid)}
    else
      _ -> retry(state)
    end
  end

  defp retry(state) do
    clear(state, state.failure_reason)
    token = make_ref()
    delay = min(30_000, 1_000 * Integer.pow(2, min(state.attempt, 5)))
    Process.send_after(self(), {:connect, token}, delay)

    %{state | timer: token, attempt: state.attempt + 1, generation: make_ref()}
    |> then(fn state ->
      clear(state, state.failure_reason)
      state
    end)
  end

  defp clear(state, reason) do
    :ets.insert(
      state.table,
      {:cache, %{generation: state.generation, frames: [], bytes: 0, reason: reason}}
    )
  end

  @impl true
  def terminate(_, state) do
    cond do
      state.pipeline -> state.runner.stop(state.pipeline)
      true -> nil
    end

    :ok
  catch
    :exit, _ -> :ok
  end
end

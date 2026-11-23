defmodule Sentinel.Monitoring.Stream do
  @moduledoc "One supervised, demand-driven conversion per camera/quality."
  use GenServer, restart: :temporary

  alias Sentinel.Monitoring

  def start_link(options) do
    key = Keyword.fetch!(options, :key)

    GenServer.start_link(__MODULE__, options,
      name: {:via, Registry, {Sentinel.Monitoring.Registry, key}}
    )
  end

  def file(pid, filename) do
    GenServer.call(pid, {:file, filename})
  catch
    :exit, {reason, {GenServer, :call, _args}}
    when reason in [:noproc, :normal, :shutdown, :timeout] ->
      {:error, :stream_unavailable}
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    {id, quality, engine} =
      case Keyword.fetch!(options, :key) do
        {id, quality} -> {id, quality, "off"}
        {id, quality, engine} -> {id, quality, engine}
      end

    root = Keyword.get(options, :directory, Keyword.fetch!(Monitoring.config(), :hls_directory))

    directory =
      Path.join([
        root,
        id,
        quality,
        engine,
        Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      ])

    state = %{
      directory: directory,
      engine: engine,
      detection_status: initial_detection_status(engine),
      source_url: Keyword.fetch!(options, :source_url),
      runner: Keyword.get(options, :pipeline_module, Sentinel.Monitoring.Pipeline),
      pipeline: nil,
      pipeline_supervisor: nil,
      monitor: nil,
      last_access: now(),
      started_at: now(),
      ready?: false,
      idle_ms: Keyword.get(options, :idle_ms, 60_000),
      stall_ms: Keyword.get(options, :stall_ms, 30_000),
      progress_token: nil,
      last_progress: now(),
      error: :warming_up
    }

    Process.send_after(self(), :check_idle, check_interval(state))
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: connect(state)

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state.detection_status, state}

  def handle_call({:file, filename}, _from, state) do
    result =
      cond do
        state.ready? -> File.read(Path.join(state.directory, filename))
        true -> {:error, state.error}
      end

    {:reply, result, %{state | last_access: now()}}
  end

  @impl true
  def handle_cast(:retry_detector, state) do
    retry_detector(state.pipeline)

    {:noreply, state}
  end

  @impl true
  def handle_info({:pipeline_ready, pid}, %{pipeline: pid} = state) do
    {:noreply, %{state | ready?: true, error: nil}}
  end

  def handle_info({:pipeline_error, pid, reason}, %{pipeline: pid} = state) do
    {:noreply, %{state | error: reason, ready?: false}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor: ref} = state) do
    Process.send_after(self(), :connect, 3_000)

    {:noreply,
     %{
       state
       | pipeline: nil,
         pipeline_supervisor: nil,
         monitor: nil,
         ready?: false,
         error:
           case state.error do
             :unsupported_codec -> :unsupported_codec
             _ -> :stream_unavailable
           end
     }}
  end

  def handle_info(:connect, state), do: connect(state)

  def handle_info(:check_idle, state) do
    token = progress_token(state.directory)

    state =
      cond do
        token != state.progress_token -> %{state | progress_token: token, last_progress: now()}
        true -> state
      end

    cond do
      now() - state.last_access >= state.idle_ms ->
        {:stop, :normal, state}

      state.pipeline != nil and now() - state.last_progress >= state.stall_ms ->
        state.runner.stop(state.pipeline)
        Process.send_after(self(), :check_idle, check_interval(state))
        {:noreply, %{state | ready?: false, error: :stream_unavailable}}

      true ->
        Process.send_after(self(), :check_idle, check_interval(state))
        {:noreply, state}
    end
  end

  def handle_info({:detection_status, pid, status}, %{pipeline: pid} = state) do
    {:noreply, %{state | detection_status: status}}
  end

  def handle_info({:detection_status, _old_pid, _status}, state), do: {:noreply, state}

  def handle_info({:pipeline_ready, _old_pid}, state), do: {:noreply, state}
  def handle_info({:pipeline_error, _old_pid, _reason}, state), do: {:noreply, state}

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    stop_pipeline(state)

    # This directory is created and owned exclusively by this worker.
    File.rm_rf(state.directory)
    :ok
  end

  defp connect(state) do
    # The previous pipeline has exited. Discard its manifests before publishing
    # a new generation; old fragments must never mix with a new live timeline.
    File.rm_rf!(state.directory)
    File.mkdir_p!(state.directory)
    generation = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    options = %{
      source_url: state.source_url,
      directory: state.directory,
      owner: self(),
      generation: generation,
      engine: state.engine
    }

    case state.runner.start(options) do
      {:ok, supervisor, pipeline} ->
        {:noreply,
         %{
           state
           | pipeline: pipeline,
             pipeline_supervisor: supervisor,
             monitor: Process.monitor(pipeline),
             started_at: now(),
             last_progress: now(),
             progress_token: nil,
             ready?: false,
             detection_status: initial_detection_status(state.engine)
         }}

      {:error, _reason} ->
        Process.send_after(self(), :connect, 3_000)
        {:noreply, %{state | error: :stream_unavailable}}
    end
  end

  defp initial_detection_status("off"), do: :off
  defp initial_detection_status(_engine), do: :loading
  defp retry_detector(nil), do: nil
  defp retry_detector(pipeline), do: send(pipeline, :retry_detector)
  defp stop_pipeline(%{pipeline: nil}), do: nil
  defp stop_pipeline(state), do: state.runner.stop(state.pipeline)

  defp check_interval(state), do: min(5_000, min(state.idle_ms, state.stall_ms))

  defp progress_token(directory) do
    directory
    |> Path.join("*.m4s")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      case File.stat(path, time: :posix) do
        {:ok, stat} -> {path, stat.mtime, stat.size}
        {:error, _reason} -> nil
      end
    end)
    |> Enum.sort()
  end

  defp now, do: System.monotonic_time(:millisecond)
end

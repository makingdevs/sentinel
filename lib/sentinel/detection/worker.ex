defmodule Sentinel.Detection.Worker do
  @moduledoc "Supervised per-stream backend. Its owner sends at most one outstanding frame."
  use GenServer, restart: :temporary, shutdown: 130_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(opts, :owner)
    ref = Process.monitor(owner)

    default_adapter =
      case Keyword.fetch!(opts, :engine) do
        "python" -> Sentinel.Detection.Python
        "elixir" -> Sentinel.Detection.Elixir
      end

    adapter = Keyword.get(opts, :adapter, default_adapter)
    {:ok, %{owner: owner, ref: ref, adapter: adapter, model: nil}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    case external(fn -> state.adapter.load() end) do
      {:ok, model} ->
        send(state.owner, {:detector_ready, self()})
        {:noreply, %{state | model: model}}

      {:error, _} ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:infer, frame}, state) do
    started = System.monotonic_time(:microsecond)
    result = external(fn -> state.adapter.infer(state.model, frame) end)
    elapsed = System.monotonic_time(:microsecond) - started

    send(
      state.owner,
      {:detector_result, self(), frame.frame_id, frame.pts, frame.captured_at, result, elapsed}
    )

    case result do
      {:ok, _} -> {:noreply, state}
      {:error, _} -> {:stop, :normal, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{ref: ref} = state), do: {:stop, :normal, state}
  def handle_info({:EXIT, _port, _reason}, state), do: {:stop, :normal, state}
  def handle_info({_port, {:exit_status, _}}, state), do: {:stop, :normal, state}

  @impl true
  def terminate(_reason, %{model: nil}), do: :ok
  def terminate(_reason, state), do: state.adapter.close(state.model)

  # Only library/IPC boundaries are rescued; internal state errors are not hidden.
  defp external(fun) do
    fun.()
  rescue
    _error in [ArgumentError, RuntimeError, ErlangError, MatchError] -> {:error, :backend_failed}
  end
end

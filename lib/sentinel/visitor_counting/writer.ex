defmodule Sentinel.VisitorCounting.Writer do
  @moduledoc "Finite ETS slots admit frame references before messaging. IO occurs only in this supervised server."
  use GenServer
  require Logger
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.{Encoder, Persistence}
  @table __MODULE__

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def enqueue(event) do
    capacity = :ets.lookup_element(@table, :capacity, 2)
    token = make_ref()

    slot =
      Enum.find(1..capacity, fn slot ->
        :ets.insert_new(@table, {{:job, slot}, token, event, 0, :selecting})
      end)

    if slot do
      event = Sentinel.VisitorCounting.SnapshotSelector.freeze(event)
      :ets.insert(@table, {{:job, slot}, token, event, 0, :ready})
      send(__MODULE__, :drain)
      :ok
    else
      metric(event.attrs.camera_id, :dropped)
      {:error, :saturated}
    end
  rescue
    ArgumentError ->
      :telemetry.execute([:sentinel, :visitor_counting, :write], %{dropped: 1}, %{
        camera_id: event.attrs.camera_id,
        reason: :writer_unavailable
      })

      {:error, :unavailable}
  end

  def stats(camera_id) do
    jobs = :ets.match_object(@table, {{:job, :_}, :_, :_, :_, :_})

    measurements =
      Map.new([:saved, :dropped, :failures], fn key ->
        value =
          case :ets.lookup(@table, {:metric, camera_id, key}) do
            [{_, n}] -> n
            [] -> 0
          end

        {key, value}
      end)

    Map.merge(measurements, %{
      queued: length(jobs),
      capacity: :ets.lookup_element(@table, :capacity, 2)
    })
  rescue
    ArgumentError -> %{saved: 0, dropped: 0, failures: 0, queued: 0, capacity: 0}
  end

  @impl true
  def init(opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])

    capacity =
      max(1, min(Keyword.get(opts, :capacity, VisitorCounting.config(:queue_capacity, 8)), 128))

    :ets.insert(@table, {:capacity, capacity})

    {:ok,
     %{
       persist: Keyword.get(opts, :persist, &persist/1),
       retry_ms: Keyword.get(opts, :retry_ms, 1_000)
     }}
  end

  @impl true
  def handle_info(:drain, state) do
    case :ets.match_object(@table, {{:job, :_}, :_, :_, :_, :ready}) |> List.first() do
      nil ->
        {:noreply, state}

      {key, token, event, attempt, :ready} ->
        case state.persist.(event) do
          {:ok, saved, inserted?} ->
            :ets.delete(@table, key)

            if inserted? == :inserted do
              metric(event.attrs.camera_id, :saved)

              Phoenix.PubSub.broadcast(
                Sentinel.PubSub,
                "visitor_events",
                {:passage_saved, saved.id}
              )
            end

          {:error, _reason} ->
            metric(event.attrs.camera_id, :failures)

            if attempt < 2 do
              :ets.insert(@table, {key, token, event, attempt + 1, :waiting})

              Process.send_after(
                self(),
                {:retry, key, token},
                state.retry_ms * Integer.pow(2, attempt)
              )
            else
              :ets.delete(@table, key)
              metric(event.attrs.camera_id, :dropped)

              Logger.warning("Visitor snapshot discarded after three failed writes",
                camera_id: event.attrs.camera_id
              )
            end
        end

        {:noreply, state}
    end
  end

  def handle_info({:retry, key, token}, state) do
    case :ets.lookup(@table, key) do
      [{^key, ^token, event, attempt, :waiting}] ->
        :ets.insert(@table, {key, token, event, attempt, :ready})
        send(self(), :drain)

      _ ->
        :ok
    end

    {:noreply, state}
  end

  defp persist(%{jpeg: jpeg, attrs: attrs}), do: Persistence.save(attrs, jpeg)

  defp persist(event) do
    with {:ok, jpeg} <- Encoder.encode(event), do: Persistence.save(event.attrs, jpeg)
  rescue
    _error in [ArgumentError, RuntimeError, ErlangError, MatchError] -> {:error, :encoding_failed}
  end

  defp metric(camera_id, key) do
    :ets.update_counter(@table, {:metric, camera_id, key}, {2, 1}, {{:metric, camera_id, key}, 0})

    :telemetry.execute([:sentinel, :visitor_counting, :write], %{key => 1}, %{
      camera_id: camera_id
    })
  end
end

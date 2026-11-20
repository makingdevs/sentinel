defmodule Sentinel.VisitorCounting.Retention do
  @moduledoc "Finite retention in bounded batches. Delete rows first, then files; file errors remain reportable orphans."
  use GenServer
  require Logger
  import Ecto.Query
  alias Sentinel.{Repo, VisitorCounting}
  alias Sentinel.VisitorCounting.{PassageEvent, Snapshots}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_opts) do
    Process.send_after(self(), :prune, 60_000)
    {:ok, nil}
  end

  @impl true
  def handle_info(:prune, state) do
    case prune(dry_run: false) do
      %{file_errors: []} -> :ok
      _ -> Logger.warning("Visitor retention needs reconciliation; run mix visitors.retention")
    end

    Process.send_after(self(), :prune, 60_000)
    {:noreply, state}
  end

  def prune(opts \\ []) do
    days = Keyword.get(opts, :days, VisitorCounting.config(:retention_days, 7))

    if not is_integer(days) or days < 1 or days > 365,
      do: raise(ArgumentError, "retention must be 1..365 days")

    cutoff = DateTime.add(Keyword.get(opts, :now, DateTime.utc_now()), -days * 86_400)

    query =
      from e in PassageEvent,
        where: e.crossed_at < ^cutoff,
        order_by: [asc: e.crossed_at, asc: e.id],
        limit: 100

    if Keyword.get(opts, :dry_run, true) do
      %{dry_run: true, candidates: Repo.all(query), deleted: 0, file_errors: []}
    else
      {:ok, keys} =
        Repo.transaction(fn ->
          events = Repo.all(from e in query, lock: "FOR UPDATE SKIP LOCKED")
          ids = Enum.map(events, & &1.id)
          Repo.delete_all(from e in PassageEvent, where: e.id in ^ids)
          Enum.map(events, & &1.snapshot_key)
        end)

      if keys != [] do
        Phoenix.PubSub.broadcast(Sentinel.PubSub, "visitor_events", :passages_pruned)
      end

      errors =
        Enum.flat_map(keys, fn key ->
          case Snapshots.delete(key) do
            :ok -> []
            {:error, reason} -> [{key, reason}]
          end
        end)

      %{dry_run: false, deleted: length(keys), file_errors: errors}
    end
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, error.__struct__}
  end

  @doc "Read-only report; includes in-flight files, so never delete from this report without reconciliation."
  def orphans do
    case File.ls(Snapshots.root()) do
      {:ok, files} ->
        files
        |> Enum.filter(&Regex.match?(~r/\A[0-9a-f]{64}\.jpg\z/, &1))
        |> Enum.chunk_every(100)
        |> Enum.flat_map(fn keys ->
          referenced =
            Repo.all(
              from e in PassageEvent, where: e.snapshot_key in ^keys, select: e.snapshot_key
            )
            |> MapSet.new()

          Enum.reject(keys, &MapSet.member?(referenced, &1))
        end)

      {:error, :enoent} ->
        []

      {:error, reason} ->
        {:error, reason}
    end
  end
end

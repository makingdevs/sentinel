defmodule Sentinel.VisitorCounting.Persistence do
  @moduledoc "File ownership and DB deduplication for a supervised writer, outside media callbacks."
  alias Sentinel.{Repo, VisitorCounting}
  alias Sentinel.VisitorCounting.Snapshots

  def save(attrs, jpeg) do
    key = Snapshots.new_key()
    save_with_key(attrs, jpeg, key)
  end

  defp save_with_key(attrs, jpeg, key) do
    result =
      Repo.transaction(fn ->
        # Serialize identical keys across processes/nodes before creating an image.
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [attrs.dedupe_key])

        case VisitorCounting.event_by_key(attrs.dedupe_key) do
          nil ->
            with :ok <- Snapshots.write(key, jpeg),
                 {:ok, event, status} <-
                   VisitorCounting.create_event(Map.put(attrs, :snapshot_key, key)) do
              case status do
                :existing -> Snapshots.delete(key)
                _ -> nil
              end

              {event, status}
            else
              {:error, reason} -> Repo.rollback(reason)
            end

          event ->
            {event, :existing}
        end
      end)

    case result do
      {:ok, {event, status}} ->
        {:ok, event, status}

      {:error, reason} ->
        Snapshots.delete(key)
        {:error, reason}
    end
  rescue
    error in Postgrex.Error ->
      Snapshots.delete(key)
      {:error, error.__struct__}

    error in DBConnection.ConnectionError ->
      # Connection loss during COMMIT is ambiguous. Keep the file for reconciliation
      # rather than risk deleting the image of an event that actually committed.
      {:error, error.__struct__}
  end
end

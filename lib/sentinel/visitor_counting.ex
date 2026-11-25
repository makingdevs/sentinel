defmodule Sentinel.VisitorCounting do
  @moduledoc "Versioned camera rules and idempotent passage history. Counts crossings, not identities."
  import Ecto.Query
  alias Sentinel.Repo
  alias Sentinel.VisitorCounting.{PassageEvent, Rule}

  def config(key, default),
    do: Application.get_env(:sentinel, :visitor_counting, []) |> Keyword.get(key, default)

  def get_rule(camera_id), do: Repo.get_by(Rule, camera_id: camera_id)
  def list_rules, do: Repo.all(from r in Rule, order_by: r.camera_id)
  def enabled_rules, do: Repo.all(from r in Rule, where: r.enabled, order_by: r.camera_id)

  def active_camera_ids do
    Repo.all(
      from r in Rule,
        join: camera in Sentinel.Monitoring.Camera,
        on: camera.id == r.camera_id,
        where: r.enabled and is_nil(camera.archived_at),
        select: r.camera_id
    )
    |> Enum.filter(&(Sentinel.VisitorCounting.Manager.status(&1) == :active))
  end

  def change_rule(camera_id, attrs \\ %{}) do
    (get_rule(camera_id) || %Rule{camera_id: camera_id}) |> Rule.changeset(attrs)
  end

  def configure_rule(camera_id, attrs) do
    camera_id
    |> change_rule(attrs)
    |> Repo.insert_or_update(stale_error_field: :revision)
    |> notify_rule()
  end

  defp notify_rule({:ok, rule} = result) do
    Phoenix.PubSub.broadcast(Sentinel.PubSub, "visitor_rules", {:rule_changed, rule.camera_id})
    result
  end

  defp notify_rule(error), do: error

  @doc "Internal trusted attributes only. The unique DB index is the final race protection."
  def create_event(attrs) do
    case Repo.insert(PassageEvent.changeset(attrs),
           on_conflict: :nothing,
           conflict_target: :dedupe_key,
           returning: true
         ) do
      {:ok, %{id: nil}} ->
        {:ok, Repo.get_by!(PassageEvent, dedupe_key: attrs.dedupe_key), :existing}

      {:ok, event} ->
        {:ok, event, :inserted}

      error ->
        error
    end
  end

  def get_event(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
    do: Repo.get(PassageEvent, id)

  def get_event(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> get_event(id)
      _ -> nil
    end
  end

  def get_event(_), do: nil
  def event_by_key(key), do: Repo.get_by(PassageEvent, dedupe_key: key)

  def list_events(filters \\ %{}, page \\ 1) do
    page =
      cond do
        is_integer(page) -> max(1, min(page, 10000))
        true -> 1
      end

    filters
    |> event_query()
    |> order_by([e], desc: e.crossed_at, desc: e.id)
    |> limit(24)
    |> offset(^((page - 1) * 24))
    |> Repo.all()
  end

  def totals(filters \\ %{}) do
    counts =
      filters
      |> event_query()
      |> group_by([e], e.direction)
      |> select([e], {e.direction, count(e.id)})
      |> Repo.all()
      |> Map.new()

    %{entry: Map.get(counts, "entry", 0), exit: Map.get(counts, "exit", 0)}
  end

  def event_query(filters) do
    Enum.reduce(filters, PassageEvent, fn
      {"camera_id", id}, q when is_binary(id) and id != "" -> where(q, [e], e.camera_id == ^id)
      {"direction", dir}, q when dir in ~w(entry exit) -> where(q, [e], e.direction == ^dir)
      {"from", %DateTime{} = date}, q -> where(q, [e], e.crossed_at >= ^date)
      {"until", %DateTime{} = date}, q -> where(q, [e], e.crossed_at < ^date)
      _, q -> q
    end)
  end
end

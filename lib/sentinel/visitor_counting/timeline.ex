defmodule Sentinel.VisitorCounting.Timeline do
  @moduledoc "Bounded UTC image activity queries. All grouping happens in PostgreSQL."
  alias Sentinel.Repo

  @page_size 24
  @filtered """
  SELECT id, camera_id, direction, COALESCE(snapshot_received_at, crossed_at) AS image_at
  FROM passage_events
  WHERE COALESCE(snapshot_received_at, crossed_at) >= $1
    AND COALESCE(snapshot_received_at, crossed_at) < $2
    AND ($3::text IS NULL OR camera_id = $3)
    AND ($4::text IS NULL OR direction = $4)
  """
  @groups """
  WITH filtered AS (
  #{@filtered}
  ), previous AS (
    SELECT *, lag(image_at) OVER (PARTITION BY camera_id ORDER BY image_at, id) AS previous_at
    FROM filtered
  ), numbered AS (
    SELECT *, sum(CASE WHEN previous_at IS NULL OR image_at - previous_at > interval '120 seconds'
                       THEN 1 ELSE 0 END)
      OVER (PARTITION BY camera_id ORDER BY image_at, id ROWS UNBOUNDED PRECEDING) AS group_number
    FROM previous
  ), groups AS (
    SELECT camera_id, group_number, min(image_at) AS started_at, max(image_at) AS ended_at,
           count(*) AS image_count, min(id) AS anchor_id
    FROM numbered GROUP BY camera_id, group_number
  )
  """

  def bounds(%Date{} = date) do
    with {:ok, start_at} <- DateTime.new(date, ~T[00:00:00], "Etc/UTC"),
         {:ok, end_at} <- DateTime.new(Date.add(date, 1), ~T[00:00:00], "Etc/UTC") do
      {:ok, {start_at, end_at}}
    end
  end

  def bounds(day) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> bounds(date)
      _ -> {:error, :invalid_day}
    end
  end

  def bounds(_), do: {:error, :invalid_day}

  def activity(day, filters \\ %{}, page \\ 1) do
    with {:ok, params} <- params(day, filters),
         {:ok, density} <-
           Repo.query(
             """
             WITH filtered AS (#{@filtered})
             SELECT floor(extract(epoch FROM (image_at - $1)) / 300)::integer AS bin, count(*)
             FROM filtered GROUP BY bin ORDER BY bin
             """,
             params
           ),
         {:ok, result} <-
           Repo.query(
             @groups <>
               """
               SELECT camera_id, started_at, ended_at, image_count, anchor_id, count(*) OVER ()
               FROM groups ORDER BY started_at, camera_id, anchor_id LIMIT 24 OFFSET $5
               """,
             params ++ [offset(page)]
           ),
         {:ok, totals} <-
           Repo.query(
             @groups <> "SELECT count(*), COALESCE(sum(image_count), 0)::bigint FROM groups",
             params
           ) do
      counts = Map.new(density.rows, fn [bin, count] -> {bin, count} end)
      [[group_count, image_count]] = totals.rows

      groups =
        Enum.map(result.rows, fn [camera, start_at, end_at, count, anchor, _] ->
          %{
            id: anchor,
            camera_id: camera,
            started_at: utc(start_at),
            ended_at: utc(end_at),
            image_count: count
          }
        end)

      {:ok,
       %{
         bins: for(bin <- 0..287, do: %{id: bin, count: Map.get(counts, bin, 0)}),
         groups: groups,
         group_count: group_count,
         image_count: image_count,
         page: page_number(page),
         page_size: @page_size
       }}
    end
  end

  def group(day, filters, id)
      when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 do
    with {:ok, params} <- params(day, filters),
         {:ok, result} <-
           Repo.query(
             @groups <> "SELECT camera_id, started_at, ended_at FROM groups WHERE anchor_id = $5",
             params ++ [id]
           ) do
      case result.rows do
        [[camera, start_at, end_at]] ->
          {:ok, %{camera_id: camera, started_at: utc(start_at), ended_at: utc(end_at)}}

        [] ->
          {:error, :invalid_selection}
      end
    end
  end

  def group(_, _, _), do: {:error, :invalid_selection}

  def totals(day, filters) do
    with {:ok, params} <- params(day, filters),
         {:ok, result} <-
           Repo.query(
             "WITH filtered AS (#{@filtered}) SELECT direction, count(*) FROM filtered GROUP BY direction",
             params
           ) do
      counts = Map.new(result.rows, fn [direction, count] -> {direction, count} end)
      {:ok, %{entry: Map.get(counts, "entry", 0), exit: Map.get(counts, "exit", 0)}}
    end
  end

  def images(day, filters \\ %{}, selection \\ nil, page \\ 1) do
    with {:ok, params} <- params(day, filters),
         {:ok, predicate, selection_params} <- selection(selection),
         {:ok, result} <-
           Repo.query(
             @groups <>
               """
               , page AS (
                 SELECT n.id, n.image_at FROM numbered n JOIN groups g
                   ON n.camera_id = g.camera_id AND n.group_number = g.group_number
                 WHERE #{predicate}
                 ORDER BY n.image_at, n.id LIMIT 24 OFFSET $#{5 + length(selection_params)}
               )
               SELECT e.* FROM page JOIN passage_events e ON e.id = page.id
               ORDER BY page.image_at, page.id
               """,
             params ++ selection_params ++ [offset(page)]
           ) do
      events =
        Enum.map(
          result.rows,
          &Repo.load(Sentinel.VisitorCounting.PassageEvent, {result.columns, &1})
        )

      {:ok, events}
    end
  end

  defp selection({:group, id, %DateTime{} = start_at, %DateTime{} = end_at})
       when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807 do
    if DateTime.compare(start_at, end_at) != :gt,
      do:
        {:ok, "g.anchor_id = $5 AND n.image_at >= $6 AND n.image_at <= $7",
         [id, DateTime.to_naive(start_at), DateTime.to_naive(end_at)]},
      else: {:error, :invalid_selection}
  end

  defp selection(nil), do: {:ok, "true", []}

  defp selection({:group, id}) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
    do: {:ok, "g.anchor_id = $5", [id]}

  defp selection({:bin, bin}) when is_integer(bin) and bin in 0..287,
    do: {:ok, "floor(extract(epoch FROM (n.image_at - $1)) / 300)::integer = $5", [bin]}

  defp selection(_), do: {:error, :invalid_selection}

  defp params(day, filters) when is_map(filters) do
    with {:ok, {start_at, end_at}} <- bounds(day) do
      camera = Map.get(filters, "camera_id")
      direction = Map.get(filters, "direction")

      if (is_nil(camera) or is_binary(camera)) and direction in [nil, "", "entry", "exit"] do
        {:ok,
         [DateTime.to_naive(start_at), DateTime.to_naive(end_at), blank(camera), blank(direction)]}
      else
        {:error, :invalid_filters}
      end
    end
  end

  defp params(_, _), do: {:error, :invalid_filters}
  defp blank(""), do: nil
  defp blank(value), do: value
  defp page_number(page) when is_integer(page), do: max(1, min(page, 10_000))
  defp page_number(_), do: 1
  defp offset(page), do: (page_number(page) - 1) * @page_size
  defp utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp utc(value), do: value
end

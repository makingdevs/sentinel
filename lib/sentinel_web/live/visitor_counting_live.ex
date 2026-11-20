defmodule SentinelWeb.VisitorCountingLive do
  use SentinelWeb, :live_view
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.{Filters, Timeline}
  @filter_keys ~w(camera_id direction from until mode day)
  @state_keys @filter_keys ++ ~w(page group_page group bin selection_from selection_until)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_events")
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "camera_catalog")
      Process.send_after(self(), :retention_refresh, 60_000)
    end

    changeset = Filters.changeset(%{})
    cameras = if connected?(socket), do: Sentinel.Monitoring.camera_options(), else: []

    {:ok,
     socket
     |> assign(
       page_title: "Historial de cruces",
       current_scope: nil,
       filters: Ecto.Changeset.apply_changes(changeset),
       form: to_form(changeset, as: :filters),
       camera_metadata: %{},
       camera_options: [{"Todas las cámaras", ""} | cameras],
       page: 1,
       group_page: 1,
       totals: %{entry: 0, exit: 0},
       count: 0,
       event: nil,
       event_id: nil,
       url_params: %{},
       peak: 1,
       bins: [],
       group_count: 0,
       image_count: 0,
       refresh_pending?: false,
       loading?: false,
       query_error?: false,
       selection: nil,
       selection_notice?: false,
       refresh_timer: nil
     )
     |> stream(:groups, [])
     |> stream(:events, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    changeset = Filters.changeset(Map.take(params, @filter_keys))

    case Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, filters} ->
        socket =
          socket
          |> assign(
            filters: filters,
            form: to_form(changeset, as: :filters),
            url_params: Map.take(params, @state_keys),
            camera_metadata: camera_metadata(),
            event_id: safe_event_id(params["event_id"]),
            page: page(params["page"]),
            group_page: page(params["group_page"])
          )

        {:noreply, if(connected?(socket), do: refresh(socket), else: socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :filters))}
    end
  end

  defp camera_metadata do
    Sentinel.Monitoring.admin_cameras()
    |> Map.new(fn entry ->
      camera = entry.camera
      {camera.id, %{label: camera.label, branch: camera.branch, color: camera.color}}
    end)
  rescue
    _ -> %{}
  end

  def channel_color(color), do: Sentinel.Monitoring.Camera.color_value(color)

  def bin_description(bin, metadata) do
    channel_counts =
      Enum.map_join(bin.cameras, ", ", fn camera ->
        name = get_in(metadata, [camera.camera_id, :label]) || camera.camera_id
        "#{name}: #{camera.count}"
      end)

    base = "#{bin_time(bin.id)} CST: #{bin.count} imágenes"
    if channel_counts == "", do: base, else: base <> ". " <> channel_counts
  end

  @impl true
  def handle_event("filter", %{"filters" => attrs}, socket) do
    changeset = Filters.changeset(attrs)

    case Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, filters} ->
        params =
          filters
          |> Map.from_struct()
          |> Map.take(Enum.map(@filter_keys, &String.to_existing_atom/1))
          |> Map.new(fn {key, value} -> {Atom.to_string(key), to_string(value)} end)

        {:noreply, push_patch(socket, to: history_path(params))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :filters))}
    end
  end

  def handle_event("page", %{"direction" => direction}, socket)
      when direction in ~w(next previous) do
    delta = if direction == "next", do: 1, else: -1
    {:noreply, patch(socket, %{"page" => to_string(page(socket.assigns.page + delta))})}
  end

  def handle_event("group_page", %{"direction" => direction}, socket)
      when direction in ~w(next previous) do
    delta = if direction == "next", do: 1, else: -1

    {:noreply,
     patch(socket, %{"group_page" => to_string(page(socket.assigns.group_page + delta))})}
  end

  def handle_event("select_group", %{"id" => id}, socket),
    do: {:noreply, patch_selection(socket, %{"group" => id})}

  def handle_event("select_bin", %{"id" => id}, socket),
    do: {:noreply, patch_selection(socket, %{"bin" => id})}

  def handle_event("reset_selection", _, socket), do: {:noreply, patch_selection(socket, %{})}
  def handle_event("retry", _, socket), do: {:noreply, refresh(socket)}

  defp patch_selection(socket, selection) do
    params =
      socket.assigns.url_params
      |> Map.drop(~w(group bin selection_from selection_until page))
      |> Map.merge(selection)

    push_patch(socket, to: history_path(params))
  end

  defp patch(socket, updates),
    do: push_patch(socket, to: history_path(Map.merge(socket.assigns.url_params, updates)))

  @impl true
  def handle_info({:camera_changed, _id}, socket) do
    {:noreply,
     socket
     |> assign(:camera_metadata, camera_metadata())
     |> refresh()}
  end

  def handle_info({:passage_saved, _}, socket), do: {:noreply, schedule_refresh(socket)}
  def handle_info(:passages_pruned, socket), do: {:noreply, schedule_refresh(socket)}

  def handle_info(:retention_refresh, socket) do
    Process.send_after(self(), :retention_refresh, 60_000)
    {:noreply, schedule_refresh(socket)}
  end

  def handle_info({:refresh, token}, %{assigns: %{refresh_timer: {_, token}}} = socket),
    do: {:noreply, socket |> assign(:refresh_timer, nil) |> refresh()}

  def handle_info({:refresh, _}, socket), do: {:noreply, socket}

  defp schedule_refresh(%{assigns: %{refresh_timer: nil}} = socket) do
    token = make_ref()
    timer = Process.send_after(self(), {:refresh, token}, 1_000)
    assign(socket, :refresh_timer, {timer, token})
  end

  defp schedule_refresh(socket), do: socket

  defp refresh(%{assigns: %{loading?: true}} = socket),
    do: assign(socket, :refresh_pending?, true)

  defp refresh(socket) do
    filters = socket.assigns.filters
    params = socket.assigns.url_params
    page = socket.assigns.page
    group_page = socket.assigns.group_page
    event_id = socket.assigns.event_id

    socket
    |> assign(loading?: true, query_error?: false)
    |> start_async(:history, fn -> load(filters, params, page, group_page, event_id) end)
  end

  defp load(%{mode: "range"} = filters, params, page, _, event_id) do
    query = Filters.query(filters)

    %{
      events: VisitorCounting.list_events(query, page),
      totals: VisitorCounting.totals(query),
      activity: %{bins: [], groups: [], group_count: 0, image_count: 0},
      event: VisitorCounting.get_event(event_id),
      params: params,
      selection: nil,
      notice?: false
    }
  end

  defp load(filters, params, page, group_page, event_id) do
    query = %{"camera_id" => filters.camera_id, "direction" => filters.direction}

    with {:ok, activity} <- Timeline.activity(filters.day, query, group_page),
         {:ok, totals} <- Timeline.totals(filters.day, query) do
      {selection, resolved, notice?} = resolve_selection(filters.day, query, params)
      {:ok, events} = Timeline.images(filters.day, query, selection, page)

      %{
        events: events,
        totals: totals,
        activity: activity,
        event: VisitorCounting.get_event(event_id),
        params: resolved,
        selection: selection,
        notice?: notice?
      }
    end
  end

  defp resolve_selection(day, query, %{"group" => id} = params) do
    with {id, ""} <- parse_integer(id),
         {:ok, group} <- Timeline.group(day, query, id) do
      {from, until} = fixed_bounds(params, group)

      resolved =
        Map.merge(params, %{
          "selection_from" => DateTime.to_iso8601(from),
          "selection_until" => DateTime.to_iso8601(until)
        })

      {{:group, id, from, until}, resolved, false}
    else
      _ -> {nil, Map.drop(params, ~w(group selection_from selection_until page)), true}
    end
  end

  defp resolve_selection(_, _, %{"bin" => bin} = params) do
    case parse_integer(bin) do
      {bin, ""} when bin in 0..287 -> {{:bin, bin}, params, false}
      _ -> {nil, Map.delete(params, "bin"), true}
    end
  end

  defp resolve_selection(_, _, params), do: {nil, params, false}

  defp parse_integer(value) when is_binary(value), do: Integer.parse(value)
  defp parse_integer(_), do: :error

  defp parse_selection_time(value) when is_binary(value), do: DateTime.from_iso8601(value)
  defp parse_selection_time(_), do: :error

  defp fixed_bounds(params, group) do
    with {:ok, from, 0} <- parse_selection_time(params["selection_from"]),
         {:ok, until, 0} <- parse_selection_time(params["selection_until"]),
         true <- DateTime.compare(from, until) != :gt,
         true <- Sentinel.LocalTime.date(from) == Sentinel.LocalTime.date(group.started_at),
         true <- Sentinel.LocalTime.date(until) == Sentinel.LocalTime.date(group.started_at),
         true <- DateTime.compare(from, group.ended_at) != :gt,
         true <- DateTime.compare(until, group.started_at) != :lt do
      {from, until}
    else
      _ -> {group.started_at, group.ended_at}
    end
  end

  @impl true
  def handle_async(:history, _result, %{assigns: %{refresh_pending?: true}} = socket) do
    {:noreply, socket |> assign(loading?: false, refresh_pending?: false) |> refresh()}
  end

  def handle_async(:history, {:ok, %{events: events} = data}, socket) do
    activity = data.activity

    socket =
      socket
      |> assign(
        loading?: false,
        query_error?: false,
        event: data.event,
        totals: data.totals,
        count: length(events),
        peak: Enum.reduce(activity.bins, 1, &max(&1.count, &2)),
        bins: activity.bins,
        group_count: activity.group_count,
        image_count: activity.image_count,
        selection: data.selection,
        selection_notice?: data.notice?
      )
      |> stream(:events, events, reset: true)
      |> stream(:groups, activity.groups, reset: true)

    socket =
      if data.params != socket.assigns.url_params,
        do:
          push_patch(socket,
            to: history_path(data.params, socket.assigns.event_id),
            replace: true
          ),
        else: socket

    {:noreply, socket}
  end

  def handle_async(:history, {:exit, {:shutdown, :cancel}}, socket), do: {:noreply, socket}

  def handle_async(:history, _, socket),
    do: {:noreply, assign(socket, loading?: false, query_error?: true)}

  defp safe_event_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> Integer.to_string(id)
      _ -> nil
    end
  end

  defp safe_event_id(_), do: nil

  defp page(value) when is_integer(value), do: max(1, min(10_000, value))

  defp page(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> page(number)
      _ -> 1
    end
  end

  defp page(_), do: 1

  defp history_path(params, event_id \\ nil) do
    base = if event_id, do: "/visitors/events/#{event_id}", else: "/visitors"
    base <> "?" <> URI.encode_query(Map.filter(params, fn {_, value} -> is_binary(value) end))
  end

  defp detail_path(params, event_id), do: history_path(params, event_id)

  defp mode_path(params, mode),
    do:
      history_path(
        params
        |> Map.drop(~w(page group_page group bin selection_from selection_until))
        |> Map.put("mode", mode)
      )

  defp selected_group?({:group, id, _, _}, id), do: true
  defp selected_group?(_, _), do: false
  defp selected_bin?({:bin, id}, id), do: true
  defp selected_bin?(_, _), do: false

  defp bin_time(bin),
    do:
      "#{String.pad_leading(to_string(div(bin * 5, 60)), 2, "0")}:#{String.pad_leading(to_string(rem(bin * 5, 60)), 2, "0")}"

  attr :event, :any, required: true
  attr :detail, :boolean, default: false

  defp snapshot_provenance(assigns) do
    ~H"""
    <div
      id={"snapshot-provenance-#{if @detail, do: "detail", else: "card"}-#{@event.id}"}
      class="mt-3 text-xs leading-5 text-slate-400"
    >
      <span class={[
        "inline-flex rounded-md border px-2 py-0.5 font-medium",
        if(@event.snapshot_quality == "primary",
          do: "border-teal-300/30 text-teal-200",
          else: "border-slate-600 text-slate-300"
        )
      ]}>
        {case @event.snapshot_quality do
          "primary" -> "Primaria · cuadro completo"
          "secondary" -> "Secundaria · respaldo"
          _ -> "Secundaria histórica"
        end}
      </span>
      <span :if={@event.snapshot_width} class="ml-2 tabular-nums">{@event.snapshot_width} × {@event.snapshot_height} px</span>
      <p :if={@event.snapshot_fallback_reason}>
        Motivo: {fallback_label(@event.snapshot_fallback_reason)}
      </p>
      <p :if={@detail}>Cruce: {Sentinel.LocalTime.format(@event.crossed_at)} CST</p>
      <p :if={@event.snapshot_received_at}>
        Imagen recibida: {Sentinel.LocalTime.format(@event.snapshot_received_at)} CST
      </p>
      <p :if={!@event.snapshot_received_at}>Hora de recepción y dimensiones desconocidas.</p>
      <p :if={@detail and @event.snapshot_quality == "primary"}>
        Captura nativa sin recuadro de detección. La recepción aproxima el momento del cruce; no implica sincronización de exposición entre canales.
      </p>
      <p :if={@detail and @event.tracking_width}>
        Seguimiento secundario: {@event.tracking_width} × {@event.tracking_height} px
      </p>
    </div>
    """
  end

  defp fallback_label(reason) do
    Map.get(
      %{
        "missing" => "sin imagen primaria disponible",
        "unavailable" => "canal primario no disponible",
        "stale" => "imagen primaria fuera de la ventana temporal",
        "future" => "imagen primaria posterior al cuadro del cruce",
        "generation_mismatch" => "la fuente primaria cambió",
        "over_budget" => "límite de recursos",
        "oversized" => "imagen primaria excede los límites"
      },
      reason,
      "sin imagen primaria disponible"
    )
  end
end

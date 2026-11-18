defmodule SentinelWeb.VisitorCountingLive do
  use SentinelWeb, :live_view
  alias Sentinel.VisitorCounting
  alias Sentinel.VisitorCounting.Filters

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_events")
    changeset = Filters.changeset(%{})

    {:ok,
     socket
     |> assign(
       page_title: "Historial de cruces",
       current_scope: nil,
       filters: Ecto.Changeset.apply_changes(changeset),
       form: to_form(changeset, as: :filters),
       camera_options: [{"Todas las cámaras", ""} | Sentinel.Monitoring.camera_options()],
       page: 1,
       totals: %{entry: 0, exit: 0},
       count: 0,
       event: nil
     )
     |> stream(:events, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if connected?(socket) do
      event = if params["event_id"], do: VisitorCounting.get_event(params["event_id"]), else: nil
      {:noreply, socket |> assign(:event, event) |> refresh()}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => attrs}, socket) do
    changeset = Filters.changeset(attrs)

    case Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, filters} ->
        {:noreply,
         socket
         |> assign(filters: filters, page: 1, form: to_form(changeset, as: :filters))
         |> refresh()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :filters))}
    end
  end

  def handle_event("page", %{"direction" => direction}, socket)
      when direction in ["next", "previous"] do
    delta = if direction == "next", do: 1, else: -1

    {:noreply,
     socket |> assign(:page, max(1, min(10_000, socket.assigns.page + delta))) |> refresh()}
  end

  @impl true
  def handle_info({:passage_saved, _id}, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    query = Filters.query(socket.assigns.filters)
    events = VisitorCounting.list_events(query, socket.assigns.page)

    socket
    |> assign(totals: VisitorCounting.totals(query), count: length(events))
    |> stream(:events, events, reset: true)
  end
end

defmodule SentinelWeb.CameraLive do
  use SentinelWeb, :live_view

  alias Sentinel.Monitoring
  alias SentinelWeb.CountingStatusComponent

  @limit 8

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) and SentinelWeb.VisitorAccess.socket_allowed?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_status")
      Process.send_after(self(), :counting_status, 2_000)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Cámaras",
       current_scope: nil,
       visitor_access?: SentinelWeb.VisitorAccess.socket_allowed?(socket),
       selected: %{},
       camera_count: 0,
       camera_options: Monitoring.camera_options(),
       form: to_form(%{"camera_id" => ""}, as: :selection)
     )
     |> stream(:cameras, [])}
  end

  @impl true
  def handle_event("add", %{"selection" => %{"camera_id" => id}}, socket) do
    cond do
      Map.has_key?(socket.assigns.selected, id) ->
        {:noreply, socket}

      socket.assigns.camera_count >= @limit ->
        {:noreply, put_flash(socket, :error, "Puedes ver hasta ocho cámaras a la vez.")}

      true ->
        with {:ok, camera} <- Monitoring.fetch_camera(id),
             {:ok, url} <- Monitoring.player_url(id, "secundaria") do
          card =
            Map.merge(camera, %{
              quality: "secundaria",
              generation: 0,
              url: url,
              engine: "off",
              counting_form: nil,
              counting_rule: nil
            })

          {:noreply,
           socket
           |> put_card(card)
           |> assign(:form, to_form(%{"camera_id" => ""}, as: :selection))}
        else
          {:error, _reason} -> {:noreply, camera_error(socket)}
        end
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    case Map.pop(socket.assigns.selected, id) do
      {nil, _selected} ->
        {:noreply, socket}

      {card, selected} ->
        {:noreply,
         socket
         |> assign(selected: selected, camera_count: map_size(selected))
         |> stream_delete(:cameras, card)}
    end
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     socket
     |> assign(selected: %{}, camera_count: 0)
     |> stream(:cameras, [], reset: true)}
  end

  def handle_event("quality", %{"id" => id, "quality" => %{"value" => quality}}, socket) do
    update_player(socket, id, quality, false)
  end

  def handle_event("engine", %{"id" => id, "detection" => %{"engine" => engine}}, socket) do
    with {:ok, card} <- Map.fetch(socket.assigns.selected, id),
         {:ok, url} <- Monitoring.player_url(id, card.quality, engine) do
      card = %{card | engine: engine, url: url, generation: card.generation + 1}
      {:noreply, put_card(socket, card)}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Este detector no está disponible en el servidor. Prueba el otro motor o desactiva la detección."
         )}
    end
  end

  def handle_event("retry", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.selected, id) do
      {:ok, card} -> update_player(socket, id, card.quality, true)
      :error -> {:noreply, camera_error(socket)}
    end
  end

  def handle_event(
        "configure-counting",
        %{"id" => id},
        %{assigns: %{visitor_access?: true}} = socket
      ) do
    with {:ok, card} <- Map.fetch(socket.assigns.selected, id) do
      changeset = Sentinel.VisitorCounting.change_rule(id)
      {:noreply, put_counting_form(socket, card, changeset)}
    else
      _ -> {:noreply, camera_error(socket)}
    end
  end

  def handle_event(
        "line",
        %{"id" => id, "line" => line},
        %{assigns: %{visitor_access?: true}} = socket
      )
      when is_map(line) do
    with {:ok, %{counting_form: %Phoenix.HTML.Form{} = form} = card} <-
           Map.fetch(socket.assigns.selected, id) do
      attrs = Map.merge(form.params, Map.take(line, ~w(x1 y1 x2 y2)))
      changeset = Sentinel.VisitorCounting.change_rule(id, attrs) |> Map.put(:action, :validate)
      {:noreply, put_counting_form(socket, card, changeset)}
    else
      _ -> {:noreply, camera_error(socket)}
    end
  end

  def handle_event(
        "validate-counting",
        %{"id" => id, "rule" => attrs},
        %{assigns: %{visitor_access?: true}} = socket
      ) do
    with {:ok, card} <- Map.fetch(socket.assigns.selected, id) do
      changeset = Sentinel.VisitorCounting.change_rule(id, attrs) |> Map.put(:action, :validate)
      {:noreply, put_counting_form(socket, card, changeset)}
    else
      _ -> {:noreply, camera_error(socket)}
    end
  end

  def handle_event(
        "save-counting",
        %{"id" => id, "rule" => attrs},
        %{assigns: %{visitor_access?: true}} = socket
      ) do
    with {:ok, card} <- Map.fetch(socket.assigns.selected, id) do
      case Sentinel.VisitorCounting.configure_rule(id, attrs) do
        {:ok, rule} ->
          {:noreply,
           socket
           |> put_counting_form(card, Sentinel.VisitorCounting.Rule.changeset(rule, %{}))
           |> put_flash(:info, "Regla de conteo guardada.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_counting_form(socket, card, changeset)}
      end
    else
      _ -> {:noreply, camera_error(socket)}
    end
  end

  def handle_event("close-counting", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.selected, id) do
      {:ok, card} ->
        {:noreply, put_card(socket, %{card | counting_form: nil, counting_rule: nil})}

      _ ->
        {:noreply, camera_error(socket)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, camera_error(socket)}

  @impl true
  def handle_info(:counting_status, socket) do
    Process.send_after(self(), :counting_status, 2_000)

    if socket.assigns.visitor_access? do
      for {id, _card} <- socket.assigns.selected, do: refresh_counting(id)
    end

    {:noreply, socket}
  end

  def handle_info({:visitor_status, id, _status}, socket) do
    if socket.assigns.visitor_access? and Map.has_key?(socket.assigns.selected, id) do
      refresh_counting(id)
    end

    {:noreply, socket}
  end

  defp refresh_counting(id) do
    send_update(CountingStatusComponent, id: "counting-indicators-#{id}", camera_id: id)
  end

  defp put_counting_form(socket, card, changeset) do
    card =
      Map.merge(card, %{
        counting_form: to_form(changeset, as: :rule),
        counting_rule: Ecto.Changeset.apply_changes(changeset)
      })

    put_card(socket, card)
  end

  defp update_player(socket, id, quality, retry?) do
    with {:ok, card} <- Map.fetch(socket.assigns.selected, id),
         {:ok, url} <- Monitoring.player_url(id, quality, card.engine) do
      if retry? and card.engine != "off", do: Monitoring.retry_detector(id, quality, card.engine)

      if retry? or card.quality != quality do
        card = %{card | quality: quality, url: url, generation: card.generation + 1}
        {:noreply, put_card(socket, card)}
      else
        {:noreply, socket}
      end
    else
      _ -> {:noreply, camera_error(socket)}
    end
  end

  defp put_card(socket, card) do
    card = Map.put(card, :form, to_form(%{"value" => card.quality}, as: :quality))
    card = Map.put(card, :detection_form, to_form(%{"engine" => card.engine}, as: :detection))
    selected = Map.put(socket.assigns.selected, card.id, card)

    socket
    |> assign(selected: selected, camera_count: map_size(selected))
    |> stream_insert(:cameras, card)
  end

  defp camera_error(socket) do
    put_flash(
      socket,
      :error,
      "No se pudo abrir esa cámara. Revisa la selección y la configuración HLS."
    )
  end
end

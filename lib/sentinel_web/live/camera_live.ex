defmodule SentinelWeb.CameraLive do
  use SentinelWeb, :live_view

  alias Sentinel.Monitoring

  @limit 8

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Cámaras",
       current_scope: nil,
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
          card = Map.merge(camera, %{quality: "secundaria", generation: 0, url: url})

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

  def handle_event("retry", %{"id" => id}, socket) do
    case Map.fetch(socket.assigns.selected, id) do
      {:ok, card} -> update_player(socket, id, card.quality, true)
      :error -> {:noreply, camera_error(socket)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, camera_error(socket)}

  defp update_player(socket, id, quality, retry?) do
    with {:ok, card} <- Map.fetch(socket.assigns.selected, id),
         {:ok, url} <- Monitoring.player_url(id, quality) do
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

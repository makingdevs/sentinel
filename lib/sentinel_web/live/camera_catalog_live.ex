defmodule SentinelWeb.CameraCatalogLive do
  use SentinelWeb, :live_view

  alias Sentinel.Monitoring
  alias Sentinel.Monitoring.Camera

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_status")
      Phoenix.PubSub.subscribe(Sentinel.PubSub, "visitor_events")
      Process.send_after(self(), :refresh_catalog, 15_000)
    end

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:page_title, "Catálogo de cámaras")
     |> assign(:colors, Camera.colors())
     |> assign(:form, camera_form(%Camera{}))
     |> assign(:editing_id, nil)
     |> assign(:cameras, Monitoring.admin_cameras())}
  end

  @impl true
  def handle_info(:refresh_catalog, socket) do
    Process.send_after(self(), :refresh_catalog, 15_000)
    {:noreply, refresh(socket)}
  end

  def handle_info({:visitor_status, _id, _status}, socket), do: {:noreply, refresh(socket)}
  def handle_info({:passage_saved, _id}, socket), do: {:noreply, refresh(socket)}
  defp refresh(socket), do: assign(socket, :cameras, Monitoring.admin_cameras())

  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    camera = Monitoring.get_camera(id)

    {:noreply,
     assign(socket,
       editing_id: id,
       form: camera_form(camera)
     )}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, editing_id: nil, form: camera_form(%Camera{}))}
  end

  def handle_event("validate", %{"camera" => attrs}, socket) do
    camera =
      if socket.assigns.editing_id,
        do: Monitoring.get_camera(socket.assigns.editing_id),
        else: %Camera{}

    changeset = Camera.changeset(camera, attrs) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :camera))}
  end

  def handle_event("save", %{"camera" => attrs}, socket) do
    sources = %{
      "principal" => Map.get(attrs, "principal"),
      "secundaria" => Map.get(attrs, "secundaria")
    }

    case Monitoring.save_camera(Map.drop(attrs, ["principal", "secundaria"]), sources) do
      {:ok, _camera} ->
        {:noreply,
         socket
         |> assign(
           cameras: Monitoring.admin_cameras(),
           editing_id: nil,
           form: camera_form(%Camera{})
         )
         |> put_flash(:info, "Canal guardado.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :camera))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "No se pudo guardar el canal.")}
    end
  end

  def handle_event("archive", %{"id" => id}, socket) do
    case Monitoring.archive_camera(id) do
      {:ok, _} -> {:noreply, assign(socket, :cameras, Monitoring.admin_cameras())}
      _ -> {:noreply, put_flash(socket, :error, "No se pudo archivar el canal.")}
    end
  end

  def handle_event("restore", %{"id" => id}, socket) do
    case Monitoring.restore_camera(id) do
      {:ok, _} -> {:noreply, assign(socket, :cameras, Monitoring.admin_cameras())}
      _ -> {:noreply, put_flash(socket, :error, "No se pudo restaurar el canal.")}
    end
  end

  defp camera_form(camera), do: to_form(Camera.changeset(camera, %{}), as: :camera)

  def counting_text(%{counting_enabled: false}), do: "Deshabilitado"
  def counting_text(%{counting_status: :capacity}), do: "Sin capacidad"
  def counting_text(%{counting_status: :error}), do: "Sin conexión"
  def counting_text(%{counting_status: :loading}), do: "Conectando"

  def counting_text(%{counting_status: :active, last_capture: nil}),
    do: "Contando, sin eventos registrados"

  def counting_text(%{counting_status: :active}), do: "Contando"
  def counting_text(%{counting_status: :saturated}), do: "Saturado"
  def counting_text(_camera), do: "Deshabilitado"
end

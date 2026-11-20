defmodule SentinelWeb.CountingStatusComponent do
  use SentinelWeb, :live_component

  alias Sentinel.VisitorCounting.{Manager, Writer}

  @impl true
  def update(%{camera_id: camera_id} = assigns, socket) do
    {:ok,
     assign(socket,
       id: assigns.id,
       camera_id: camera_id,
       status: Manager.status(camera_id),
       stats: Writer.stats(camera_id)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <p
        id={"counting-status-#{@camera_id}"}
        class="mb-2 text-xs text-slate-400"
        aria-live="polite"
      >
        Conteo continuo: <span class="text-teal-300">{counting_status_text(@status)}</span>
        · Cola {@stats.queued}/{@stats.capacity}
      </p>
      <p
        :if={@stats.dropped > 0 or @stats.failures > 0}
        id={"counting-losses-#{@camera_id}"}
        class="mb-3 rounded-lg bg-amber-400/10 p-3 text-xs text-amber-200"
      >
        {@stats.dropped} cruces no guardados · {@stats.failures} intentos fallidos desde el arranque del escritor. El historial puede estar incompleto.
      </p>
    </div>
    """
  end

  defp counting_status_text(:disabled), do: "Deshabilitado"
  defp counting_status_text(:loading), do: "Cargando"
  defp counting_status_text(:active), do: "Contando"
  defp counting_status_text(:saturated), do: "Saturado"
  defp counting_status_text(:capacity), do: "Sin capacidad"
  defp counting_status_text(:error), do: "Sin conexión · reintentando"
end

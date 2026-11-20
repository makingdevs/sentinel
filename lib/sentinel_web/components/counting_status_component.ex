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
        class="mb-2 flex flex-wrap items-center gap-2 text-xs text-slate-400"
        aria-live="polite"
      >
        <span>Conteo continuo</span>
        <span class={status_badge_class(@status)}>{counting_status_text(@status)}</span>
        <span>Cola {@stats.queued}/{@stats.capacity}</span>
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
  defp counting_status_text(_status), do: "Estado desconocido"

  defp status_badge_class(:active),
    do:
      "rounded-full bg-emerald-400/15 px-2.5 py-1 font-medium text-emerald-300 ring-1 ring-inset ring-emerald-400/30"

  defp status_badge_class(:disabled),
    do:
      "rounded-full bg-slate-400/10 px-2.5 py-1 font-medium text-slate-300 ring-1 ring-inset ring-slate-400/20"

  defp status_badge_class(:loading),
    do:
      "rounded-full bg-sky-400/15 px-2.5 py-1 font-medium text-sky-300 ring-1 ring-inset ring-sky-400/30"

  defp status_badge_class(:saturated),
    do:
      "rounded-full bg-amber-400/15 px-2.5 py-1 font-medium text-amber-300 ring-1 ring-inset ring-amber-400/30"

  defp status_badge_class(:capacity),
    do:
      "rounded-full bg-orange-400/15 px-2.5 py-1 font-medium text-orange-300 ring-1 ring-inset ring-orange-400/30"

  defp status_badge_class(:error),
    do:
      "rounded-full bg-rose-400/15 px-2.5 py-1 font-medium text-rose-300 ring-1 ring-inset ring-rose-400/30"

  defp status_badge_class(_status),
    do:
      "rounded-full bg-slate-400/10 px-2.5 py-1 font-medium text-slate-300 ring-1 ring-inset ring-slate-400/20"
end

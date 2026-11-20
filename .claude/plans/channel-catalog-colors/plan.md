# Catálogo de canales, colores y estado de captura

Estado: completado y verificado localmente. Ver el [registro de ejecución](progress.md). Ver [evidencia](research/evidence.md) y [mapa de interacción](breadboard.md).

**Unidad de gestión.** Un canal es una cámara del catálogo. Principal y secundaria siguen siendo fuentes de esa misma cámara y comparten su color. El color identifica al canal en su estado actual, incluso al consultar cruces previos. Si falta metadata, se muestra el ID y un color neutro.

## Fase 1. Catálogo persistente

- [x] **T1 [ecto]** Agregar color validado contra una paleta nombrada y estado de archivo. Asignar colores iniciales de forma determinista a canales existentes, conservar las elecciones en reimportaciones y mantener el ID estable. Probar migración, validaciones y reimportación.
- [x] **T2 [ecto/runtime]** Agregar operaciones de lista, detalle, alta, edición, archivo y restauración en Monitoring. Guardar metadatos y fuentes en una transacción. Archivar retira el canal de nuevas sesiones, detiene consumidores existentes de ese canal y conserva historial. Restaurar vuelve a habilitar su selección y requiere reactivar el conteo explícitamente. Definir cómo reconciliar consumidores al reemplazar una fuente y probar aislamiento entre cámaras.

## Fase 2. Administración y captura

- [x] **T3 [liveview]** Crear una vista de administración bajo el acceso local existente, con enlaces desde cámaras e historial. Mostrar ID, sucursal, etiqueta, color y presencia de fuentes. Permitir configurar o reemplazar URLs RTSP con campos vacíos al editar y conservar valores si se dejan vacíos. Evitar devolver credenciales existentes al navegador o escribirlas a logs. Confirmar archivo y permitir restauración. Usar formularios con IDs únicos.
- [x] **T4 [liveview/ecto]** Mostrar por canal si el conteo está habilitado, su estado efectivo y la última captura persistida en CST. Consultar las últimas capturas en lote y refrescar indicadores con PubSub y actualización periódica acotada, sin repintar formularios. Distinguir «Contando, sin eventos registrados» de «Deshabilitado», «Sin conexión» y «Sin capacidad». Probar reinicio y un evento persistido.

## Fase 3. Identidad visual y verificación

- [x] **T5 [liveview]** Usar una etiqueta común con nombre y muestra de color en tarjetas de cámaras, catálogo, grupos, galería y detalle. Mostrar color junto al filtro seleccionado y en la leyenda cuando los selectores nativos no admitan formato uniforme. Refrescar los metadatos en vistas abiertas sin perder filtros ni reiniciar reproductores por cambios de color.
- [x] **T6 [ecto/liveview]** Calcular segmentos por intervalo y cámara en la actividad diaria. Mantener el eje CST y la altura proporcional al total. Añadir leyenda y texto accesible con nombre y conteo para intervalos de varios canales. Acotar el volumen por día, filtros y canales presentes; verificar que los segmentos suman el total y que seleccionar un intervalo conserva el comportamiento actual.
- [x] **T7 [testing]** Cubrir CRUD, acceso local, credenciales ausentes del DOM y logs, archivo con cruces existentes, colores en todas las referencias, actualización de captura y coexistencia de cámaras en un intervalo. Ejecutar pruebas focalizadas, `mix compile --warnings-as-errors`, formato y `mix precommit`. Ejecutar Credo si está configurado y revisar manualmente escritorio, móvil y teclado.

## Decisiones y riesgos

- **¿Qué pasa al eliminar un canal con historial?** La baja es un archivo reversible. Se conservan el ID, las capturas existentes y la metadata necesaria para interpretarlas. El historial mantiene filtros útiles para canales archivados.
- **¿Qué pasa si dos canales comparten un intervalo o un color?** Cada contribución tiene su propio conteo y la leyenda conserva los nombres. La paleta ofrece contraste; los nombres y el texto accesible siguen identificando el canal cuando coinciden colores.
- **¿Cómo sabemos si está capturando?** El estado del proceso indica si puede contar ahora. La última captura persistida confirma que guardó un evento. Un periodo sin cruces no se interpreta como fallo.

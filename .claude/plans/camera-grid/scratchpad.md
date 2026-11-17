# Cuadrícula de cámaras — planificación en curso

## Decisiones confirmadas
- LiveView sin autenticación durante desarrollo; seguridad en una etapa posterior.
- Varias cámaras simultáneas en cuadrícula; el usuario elige cuáles mostrar.
- Acceso desde Internet sin VPN.
- Configuración local: ocho cámaras, dos calidades por cámara; HLS y WebRTC habilitados.
- RTSP funciona desde la red privada según prueba del usuario; reproducción pública aún sin verificar.
- No copiar credenciales ni URLs de origen del DVR en artefactos o frontend.

## Investigación pendiente
- [x] Proyecto Phoenix, rutas, layout y pruebas.
- [x] Reproducción MediaMTX en navegador: HTTPS, puertos y códecs.
- [x] Infraestructura pública y catálogo de cámaras; aclarar despliegue.
- [x] Ciclo de vida del reproductor en LiveView y verificación.

Evidencia: research/findings.md. Se completó investigación documental; DNS, certificado y códecs son verificaciones operativas de la primera fase, no hechos comprobados.

No generar el plan definitivo hasta completar las investigaciones y aclaraciones necesarias.

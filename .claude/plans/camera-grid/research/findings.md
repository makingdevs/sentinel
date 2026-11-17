# Evidencia y decisiones

## Proyecto
- Phoenix ~> 1.8.16, LiveView ~> 1.2.0, Req incluido; no autenticación ni LiveViews de negocio.
- Router: `/` usa PageController; agregar `/cameras` en scope browser existente.
- Layouts.app admite current_scope nil, pero su contenedor max-w-2xl requiere una variante amplia para la cuadrícula.
- app.js integra LiveSocket y hooks; no se necesita un hook propio con la opción iframe.
- precommit compila con warnings-as-errors, revisa dependencias sin uso, formatea y ejecuta tests. Credo no está instalado.

## MediaMTX y despliegue
- Archivo local inspeccionado sin copiar sus secretos: dos sucursales, cuatro cámaras cada una, streams principal/secundario. API sólo en loopback.
- Usuario confirma AWS, puertos TCP 8888/8554/1935/8889, UDP 51820/8189; HTTPS pendiente; uso público sin VPN.
- El RTSP de ejemplo usa dirección privada; no prueba DNS público, acceso HLS ni códecs compatibles.
- HLS permite iframe por cámara con controles, autoplay, muted y playsInline; evita incorporar dependencias JS para el MVP.
- HTTPS nativo requiere hlsEncryption, hlsServerCert y hlsServerKey. Emisión/renovación del certificado es un paso separado; no se comprobó acceso a AWS ni método DNS disponible.
- URL propuesta: https://monitor.agorabarrade.cafe:8888/<path>. No requiere abrir 443 si TLS se sirve directamente en 8888. Certificado válido para el dominio.
- El iframe limita acceso a eventos internos y futura inyección de tokens; no informar estado de reproducción usando solamente onload.
- Verificar códecs reales antes de implementar: reproducción en ffplay no prueba compatibilidad del navegador; posible necesidad de H.264/configuración del DVR o transcodificación externa.

## Fuentes consultadas mediante Context7
- https://github.com/bluenviron/mediamtx/blob/main/docs/5-read/07-web-browsers.md
- https://github.com/bluenviron/mediamtx/blob/main/internal/conf/conf.go
- https://github.com/bluenviron/mediamtx/blob/main/docs/2-features/24-webrtc-specific-features.md
- https://github.com/bluenviron/mediamtx/blob/main/docs/2-features/06-remuxing-reencoding-compression.md
- Phoenix LiveView 1.2.0: documentación de streams y conservación de elementos DOM.

## Alcance
Una sola entrega, catálogo explícito configurable sin base de datos, selección temporal durante sesión LiveView, cuadrícula vacía inicial, secundaria predeterminada (supuestos propuestos). No descubrimiento remoto por API, WebRTC, grabaciones ni autenticación en esta etapa.

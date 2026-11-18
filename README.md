# Sentinel

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Monitoreo de cámaras

La cuadrícula `/cameras` usa RTSP → Membrane → HLS servido por Sentinel.
Consulta [configuración, ejecución y límites](docs/monitoring.md).
Instala el reproductor con `npm ci --prefix assets` antes de compilar assets.

## Personas y autos

La detección puede ejecutarse con Python/Ultralytics o Elixir/YOLO/Ortex, con un
selector por cámara y cajas dentro del video HLS. Consulta
[instalación, ejecución y comparación](docs/detection.md).

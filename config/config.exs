# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sentinel,
  ecto_repos: [Sentinel.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :sentinel, SentinelWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SentinelWeb.ErrorHTML, json: SentinelWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Sentinel.PubSub,
  live_view: [signing_salt: "mTnot8ND"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :sentinel, Sentinel.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  sentinel: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  sentinel: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Public camera identifiers and MediaMTX paths only; never DVR connection URLs.
config :sentinel, :monitoring,
  cameras: [
    %{
      id: "division-1",
      branch: "División",
      label: "Cámara 1",
      paths: %{
        "principal" => "division-canal-1-principal",
        "secundaria" => "division-canal-1-secundario"
      }
    },
    %{
      id: "division-2",
      branch: "División",
      label: "Cámara 2",
      paths: %{
        "principal" => "division-canal-2-principal",
        "secundaria" => "division-canal-2-secundario"
      }
    },
    %{
      id: "division-3",
      branch: "División",
      label: "Cámara 3",
      paths: %{
        "principal" => "division-canal-3-principal",
        "secundaria" => "division-canal-3-secundario"
      }
    },
    %{
      id: "division-4",
      branch: "División",
      label: "Cámara 4",
      paths: %{
        "principal" => "division-canal-4-principal",
        "secundaria" => "division-canal-4-secundario"
      }
    },
    %{
      id: "lavirgen-1",
      branch: "La Virgen",
      label: "Cámara 1",
      paths: %{
        "principal" => "lavirgen-canal-1-principal",
        "secundaria" => "lavirgen-canal-1-secundario"
      }
    },
    %{
      id: "lavirgen-2",
      branch: "La Virgen",
      label: "Cámara 2",
      paths: %{
        "principal" => "lavirgen-canal-2-principal",
        "secundaria" => "lavirgen-canal-2-secundario"
      }
    },
    %{
      id: "lavirgen-3",
      branch: "La Virgen",
      label: "Cámara 3",
      paths: %{
        "principal" => "lavirgen-canal-3-principal",
        "secundaria" => "lavirgen-canal-3-secundario"
      }
    },
    %{
      id: "lavirgen-4",
      branch: "La Virgen",
      label: "Cámara 4",
      paths: %{
        "principal" => "lavirgen-canal-4-principal",
        "secundaria" => "lavirgen-canal-4-secundario"
      }
    }
  ]

# Native CPU acceleration for bounded detector preprocessing and NMS.
config :nx, default_backend: EXLA.Backend, default_defn_options: [compiler: EXLA]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

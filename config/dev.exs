import Config

# Configure your database
config :agentleguide, Agentleguide.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agentleguide_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  types: Agentleguide.PostgrexTypes

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
# Binding to loopback ipv4 address prevents access from other machines.
config :agentleguide, AgentleguideWeb.Endpoint,
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "vw+WT1hsRIml8kMGij9+nTj/7ds5zl8XtCrrHEIWT6boExYznPdHz7sHhEGT9pCD",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:agentleguide, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:agentleguide, ~w(--watch)]}
  ]

config :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  organization_key: System.get_env("OPENAI_ORGANIZATION_KEY"),
  http_options: [recv_timeout: 30_000]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
  client_id: System.get_env("HUBSPOT_CLIENT_ID"),
  client_secret: System.get_env("HUBSPOT_CLIENT_SECRET")

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :agentleguide, AgentleguideWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/agentleguide_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :agentleguide, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Include HEEx debug annotations as HTML comments in rendered markup
  debug_heex_annotations: true,
  # Enable helpful, but potentially expensive runtime checks
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# HubSpot OAuth Configuration for Development
config :ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
  client_id: System.get_env("HUBSPOT_CLIENT_ID") || "your_hubspot_client_id_here",
  client_secret: System.get_env("HUBSPOT_CLIENT_SECRET") || "your_hubspot_client_secret_here"

# AI Service Configuration for Development - Use Ollama
# config :agentleguide,
#   ai_backend: :ollama,
#   ollama_url: "http://localhost:11434",
#   embeddings_enabled: true

config :agentleguide,
  ai_backend: :openai,
  embeddings_enabled: true

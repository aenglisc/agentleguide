# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :agentleguide,
  ecto_repos: [Agentleguide.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :agentleguide, AgentleguideWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgentleguideWeb.ErrorHTML, json: AgentleguideWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Agentleguide.PubSub,
  live_view: [signing_salt: "UOnLrdqC"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :agentleguide, Agentleguide.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  agentleguide: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  agentleguide: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "email profile https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/calendar.readonly https://www.googleapis.com/auth/calendar"
       ]},
    hubspot:
      {Ueberauth.Strategy.Hubspot,
       [
         default_scope:
           "timeline oauth crm.objects.contacts.write crm.objects.companies.write crm.lists.write crm.objects.companies.read crm.lists.read crm.objects.deals.read crm.schemas.contacts.read crm.objects.deals.write crm.objects.contacts.read"
       ]}
  ]

config :agentleguide, :hubspot_base_api_url, "https://api.hubapi.com"

# Configure Oban
config :agentleguide, Oban,
  repo: Agentleguide.Repo,
  queues: [
    default: 10,
    sync: 5,
    ai: 3
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

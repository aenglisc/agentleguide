import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :agentleguide, Agentleguide.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agentleguide_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: Agentleguide.PostgrexTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :agentleguide, AgentleguideWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "PitmTLpo99IAa5EPzb4dWKRvRfC5R/4Gs1oxu3eG9GBKOUXnC+KFBKi2sqUS34P6",
  server: false

# In test we don't send emails
config :agentleguide, Agentleguide.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Suppress specific log messages that are expected in tests
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  # Filter out expected HubSpot error logs in tests
  compile_time_purge_matching: [
    [module: Agentleguide.Services.Hubspot.HubspotService],
    [module: Agentleguide.Jobs.HubspotTokenRefreshJob],
    [module: Agentleguide.Jobs.HubspotSyncJob]
  ]

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# AI Service Configuration for Test - Use Ollama (no real API calls in tests)
config :agentleguide,
  ai_backend: :ollama,
  environment: :test,
  embeddings_enabled: false,
  # Disable HubSpot job scheduling and API calls in tests
  hubspot_service: Agentleguide.HubspotServiceMock,
  hubspot_token_refresh_scheduling: false

# Disable Oban in test mode
config :agentleguide, Oban, testing: :inline

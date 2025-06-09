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
  pool_size: 20,
  ownership_timeout: 15_000,
  timeout: 15_000,
  queue_target: 1000,
  queue_interval: 5000,
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

# AI Service Configuration for Test - Use Mock Client (no real API calls in tests)
config :agentleguide,
  ai_backend: :mock,
  environment: :test,
  embeddings_enabled: false,
  # Disable HubSpot job scheduling and API calls in tests
  hubspot_service: Agentleguide.HubspotServiceTestStub,
  hubspot_token_refresh_scheduling: false,
  # Disable Google token refresh scheduling in tests
  google_token_refresh_scheduling: false,
  gmail_http_client: Agentleguide.GmailHttpMock,
  google_auth_http_client: Agentleguide.GoogleAuthHttpMock,
  google_calendar_http_client: Agentleguide.GoogleCalendarHttpMock,
  queue_embeddings: false

# Disable Oban in test mode
config :agentleguide, Oban, testing: :inline

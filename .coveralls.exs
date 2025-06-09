# Coveralls configuration
[
  # Coverage thresholds
  minimum_coverage: 20.0,
  terminal_options: [
    file_column_width: 40
  ],

  # HTML report options
  html_options: [
    title: "Agentleguide Test Coverage Report"
  ],

  # Exclude patterns
  skip_files: [
    # Generated files
    "deps/",
    "_build/",

    # Test support files (already counted in test coverage)
    "test/support/",

    # Application configuration files
    "lib/agentleguide_web/endpoint.ex",
    "lib/agentleguide_web/gettext.ex",
    "lib/agentleguide/repo.ex",
    "lib/agentleguide/mailer.ex",
    "lib/agentleguide.ex",

    # Layout components (mostly templates)
    "lib/agentleguide_web/components/layouts.ex",
    "lib/agentleguide_web/controllers/page_html.ex",

    # UI components (mostly rendering logic, hard to test meaningfully)
    "lib/agentleguide_web/components/core_components.ex",

    # Infrastructure and configuration files (not business logic)
    "lib/agentleguide_web/endpoint.ex",
    "lib/agentleguide_web/gettext.ex",
    "lib/agentleguide/presence.ex",
    "lib/agentleguide/services/http_client_behaviour.ex",

    # External service clients that require running services
    "lib/agentleguide/services/ai/clients/ollama_client.ex",
    "lib/agentleguide/services/ai/clients/mock_client.ex"
  ]
]

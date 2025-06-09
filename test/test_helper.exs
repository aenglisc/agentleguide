ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Agentleguide.Repo, :manual)

# Set up HTTP client mocks for Google services
Mox.defmock(Agentleguide.GmailHttpMock, for: Agentleguide.HttpClientBehaviour)
Mox.defmock(Agentleguide.GoogleAuthHttpMock, for: Agentleguide.HttpClientBehaviour)
Mox.defmock(Agentleguide.GoogleCalendarHttpMock, for: Agentleguide.HttpClientBehaviour)

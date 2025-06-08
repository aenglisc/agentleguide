ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Agentleguide.Repo, :manual)

# Global test setup
Mox.defmock(Agentleguide.HubspotServiceMock, for: Agentleguide.Services.Hubspot.HubspotServiceBehaviour)

# Set up global stubs for HubSpot service to prevent real API calls
Mox.stub_with(Agentleguide.HubspotServiceMock, Agentleguide.HubspotServiceTestStub)

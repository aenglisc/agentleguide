defmodule Agentleguide.HubspotServiceTestStub do
  @moduledoc """
  Test stub for HubSpot service that provides safe default implementations
  to prevent real API calls during tests.
  """

  @behaviour Agentleguide.Services.Hubspot.HubspotServiceBehaviour

  @impl true
  def refresh_access_token(_user) do
    # Return a safe default that doesn't make API calls
    {:error, :not_implemented_in_tests}
  end

  @impl true
  def create_contact(_user, _attrs) do
    {:error, :not_implemented_in_tests}
  end

  # Add other HubSpot service methods as needed with safe defaults
  def sync_contacts(_user), do: {:ok, []}
  def get_contact(_user, _contact_id), do: {:error, :not_found}
  def debug_api_connection(_user), do: {:error, :not_implemented_in_tests}
  def debug_token_status(_user), do: {:error, :not_implemented_in_tests}
end

defmodule Agentleguide.Services.Hubspot.HubspotServiceBehaviour do
  @moduledoc """
  Behavior for HubSpot service operations.
  This allows mocking in tests while maintaining the same interface.
  """

  @callback refresh_access_token(user :: struct()) ::
              {:ok, struct()} | {:error, atom() | tuple()}

  @callback create_contact(user :: struct(), attrs :: map()) ::
              {:ok, struct()} | {:error, atom() | tuple()}
end

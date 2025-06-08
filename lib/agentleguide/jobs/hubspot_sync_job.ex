defmodule Agentleguide.Jobs.HubspotSyncJob do
  @moduledoc """
  Background job for syncing HubSpot contacts for users.
  """
  use Oban.Worker, queue: :sync, unique: [period: 600, keys: [:user_id]]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("HubspotSyncJob: User #{user_id} not found")
        :ok

      user ->
        if user.hubspot_connected_at do
          case Agentleguide.HubspotService.sync_contacts(user) do
            {:ok, count} ->
              # Only log if contacts were actually synced
              if count > 0 do
                Logger.info(
                  "HubspotSyncJob: Successfully synced #{count} contacts for user #{user.id}"
                )
              else
                Logger.debug("HubspotSyncJob: No new contacts to sync for user #{user.id}")
              end

              :ok

            {:error, reason} ->
              Logger.error(
                "HubspotSyncJob: Failed to sync contacts for user #{user.id}: #{inspect(reason)}"
              )

              {:error, reason}
          end
        else
          Logger.debug("HubspotSyncJob: User #{user.id} does not have HubSpot connected")
          :ok
        end
    end
  end

  @doc """
  Schedule HubSpot sync for a user immediately.
  Uses job uniqueness to prevent duplicate syncs within 10 minutes.
  """
  def schedule_now(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule recurring HubSpot sync for a user (every 2 hours).
  """
  def schedule_recurring(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new(schedule_in: {2, :hour})
    |> Oban.insert()
  end
end

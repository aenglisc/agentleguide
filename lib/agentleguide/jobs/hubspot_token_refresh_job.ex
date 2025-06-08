defmodule Agentleguide.Jobs.HubspotTokenRefreshJob do
  @moduledoc """
  Background job for refreshing HubSpot OAuth tokens before they expire.
  HubSpot access tokens typically expire after 30 minutes.
  """
  use Oban.Worker, queue: :sync, unique: [period: 300, keys: [:user_id]]

  require Logger

  # Allow service to be configurable for testing
  defp hubspot_service do
    Application.get_env(:agentleguide, :hubspot_service, Agentleguide.Services.Hubspot.HubspotService)
  end

  # Allow scheduling to be disabled in tests
  defp should_schedule? do
    Application.get_env(:agentleguide, :hubspot_token_refresh_scheduling, true)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("HubspotTokenRefreshJob: User #{user_id} not found")
        :ok

      user ->
        if needs_refresh?(user) do
          case hubspot_service().refresh_access_token(user) do
            {:ok, _updated_user} ->
              Logger.info(
                "HubspotTokenRefreshJob: Successfully refreshed token for user #{user.id}"
              )

              # Schedule next refresh in 25 minutes (5 minutes before expiry)
              if should_schedule?(), do: schedule_next_refresh(user_id)
              :ok

            {:error, reason} ->
              Logger.error(
                "HubspotTokenRefreshJob: Failed to refresh token for user #{user.id}: #{inspect(reason)}"
              )

              # Retry in 5 minutes on failure
              if should_schedule?(), do: schedule_retry(user_id)
              {:error, reason}
          end
        else
          # Token doesn't need refresh yet, schedule for later
          if should_schedule?(), do: schedule_next_refresh(user_id)
          :ok
        end
    end
  end

  @doc """
  Schedule token refresh for a user immediately.
  """
  def schedule_now(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule the next token refresh based on token expiry.
  Schedules refresh 5 minutes before token expires, or in 25 minutes if no expiry is set.
  """
  def schedule_next_refresh(user_id) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("Cannot schedule refresh for missing user #{user_id}")
        {:error, :user_not_found}

      user ->
        if user.hubspot_connected_at && user.hubspot_access_token do
          schedule_in_seconds =
            if user.hubspot_token_expires_at do
              # Schedule 5 minutes before expiry
              expiry_time = user.hubspot_token_expires_at
              seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())
              # At least 5 minutes, or 5 minutes before expiry
              max(300, seconds_until_expiry - 300)
            else
              # Default to 25 minutes if no expiry time is set
              1500
            end

          %{"user_id" => user_id}
          |> __MODULE__.new(schedule_in: schedule_in_seconds)
          |> Oban.insert()
        else
          {:ok, :not_needed}
        end
    end
  end

  # Schedule retry in 5 minutes on failure
  defp schedule_retry(user_id) do
    %{"user_id" => user_id}
    # 5 minutes
    |> __MODULE__.new(schedule_in: 300)
    |> Oban.insert()
  end

  # Check if token needs refresh (expires in next 10 minutes or already expired)
  defp needs_refresh?(user) do
    case user.hubspot_token_expires_at do
      nil ->
        # No expiry time set, assume it needs refresh if token exists
        !is_nil(user.hubspot_access_token)

      expiry_time ->
        # Refresh if token expires in the next 10 minutes
        seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())
        seconds_until_expiry <= 600
    end
  end
end

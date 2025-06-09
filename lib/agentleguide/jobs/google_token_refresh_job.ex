defmodule Agentleguide.Jobs.GoogleTokenRefreshJob do
  @moduledoc """
  Background job for refreshing Google OAuth tokens before they expire.
  Google access tokens typically expire after 1 hour.
  """
  use Oban.Worker, queue: :sync, unique: [period: 300, keys: [:user_id]]

  require Logger
  alias Agentleguide.Services.Google.GoogleAuthService

  # Allow service to be configurable for testing
  defp google_auth_service do
    Application.get_env(:agentleguide, :google_auth_service, GoogleAuthService)
  end

  # Allow scheduling to be disabled in tests
  defp should_schedule? do
    Application.get_env(:agentleguide, :google_token_refresh_scheduling, true)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("GoogleTokenRefreshJob: User #{user_id} not found")
        :ok

      user ->
        if needs_refresh?(user) do
          case google_auth_service().refresh_access_token(user) do
            {:ok, _updated_user} ->
              Logger.info(
                "GoogleTokenRefreshJob: Successfully refreshed token for user #{user.id}"
              )

              # Schedule next refresh in 55 minutes (5 minutes before expiry)
              if should_schedule?(), do: schedule_next_refresh(user_id)
              :ok

            {:error, reason} ->
              Logger.error(
                "GoogleTokenRefreshJob: Failed to refresh token for user #{user.id}: #{inspect(reason)}"
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
  Refreshes 5 minutes before expiry, or in 55 minutes if no expiry set.
  """
  def schedule_next_refresh(user_id) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("Cannot schedule Google token refresh for non-existent user #{user_id}")
        {:error, :user_not_found}

      user ->
        schedule_in_seconds = calculate_refresh_delay(user)

        %{"user_id" => user_id}
        |> __MODULE__.new(schedule_in: {schedule_in_seconds, :second})
        |> Oban.insert()
    end
  end

  @doc """
  Schedule a retry in 5 minutes for failed refresh attempts.
  """
  def schedule_retry(user_id) do
    Logger.info("GoogleTokenRefreshJob: Scheduling retry in 5 minutes for user #{user_id}")

    %{"user_id" => user_id}
    |> __MODULE__.new(schedule_in: {5, :minute})
    |> Oban.insert()
  end

  # Check if user's Google token needs refresh (expires in next 5 minutes)
  defp needs_refresh?(user) do
    google_auth_service().needs_refresh?(user)
  end

  # Calculate how many seconds until we should refresh the token
  # Refresh 5 minutes before expiry, or in 55 minutes if no expiry set
  defp calculate_refresh_delay(user) do
    case user.google_token_expires_at do
      nil ->
        # No expiry set, check again in 55 minutes
        55 * 60

      expiry_time ->
        # Schedule refresh 5 minutes before expiry
        seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())
        # At least 1 minute from now
        refresh_time = max(seconds_until_expiry - 300, 60)

        Logger.debug(
          "GoogleTokenRefreshJob: Token for user #{user.id} expires in #{seconds_until_expiry}s, scheduling refresh in #{refresh_time}s"
        )

        refresh_time
    end
  end
end

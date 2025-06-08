defmodule Agentleguide.Jobs.EmailSyncJob do
  @moduledoc """
  Background job for syncing Gmail emails for users.
  Adaptive sync: 5 seconds when user is online, 30 minutes when offline.
  """
  use Oban.Worker, queue: :sync, unique: [period: 300, keys: [:user_id]]

  require Logger

  @online_interval {5, :second}
  @offline_interval {30, :minute}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "adaptive" => true}}) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("EmailSyncJob: User #{user_id} not found")
        :ok

      user ->
        case Agentleguide.Services.Google.GmailService.sync_recent_emails(user) do
          {:ok, count} ->
            # Only log if emails were actually synced to reduce noise
            if count > 0 do
              Logger.info("EmailSyncJob: Successfully synced #{count} emails for user #{user.id}")
            else
              Logger.debug("EmailSyncJob: No new emails to sync for user #{user.id}")
            end

            # Schedule the next adaptive sync based on user presence
            schedule_next_adaptive_sync(user_id)
            :ok

          {:error, reason} ->
            Logger.error(
              "EmailSyncJob: Failed to sync emails for user #{user.id}: #{inspect(reason)}"
            )

            # Still schedule next sync even if this one failed
            schedule_next_adaptive_sync(user_id)
            {:error, reason}
        end
    end
  end

  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Agentleguide.Accounts.get_user(user_id) do
      nil ->
        Logger.warning("EmailSyncJob: User #{user_id} not found")
        :ok

      user ->
        case Agentleguide.Services.Google.GmailService.sync_recent_emails(user) do
          {:ok, count} ->
            # Only log if emails were actually synced to reduce noise
            if count > 0 do
              Logger.info("EmailSyncJob: Successfully synced #{count} emails for user #{user.id}")
            else
              Logger.debug("EmailSyncJob: No new emails to sync for user #{user.id}")
            end

            :ok

          {:error, reason} ->
            Logger.error(
              "EmailSyncJob: Failed to sync emails for user #{user.id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  @doc """
  Schedule email sync for a user immediately.
  Uses job uniqueness to prevent duplicate syncs within 5 minutes.
  """
  def schedule_now(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule recurring email sync for a user (every 30 minutes).
  """
  def schedule_recurring(user_id) do
    %{"user_id" => user_id}
    |> __MODULE__.new(schedule_in: @offline_interval)
    |> Oban.insert()
  end

  @doc """
  Start adaptive email sync.
  Checks every 5 seconds when user is online, every 30 minutes when offline.
  """
  def start_adaptive_sync(user_id) do
    Logger.info("Starting adaptive email sync for user #{user_id}")
    schedule_next_adaptive_sync(user_id)
  end

  @doc """
  Stop adaptive email sync for a user.
  """
  def stop_adaptive_sync(user_id) do
    Logger.info("Stopping adaptive email sync for user #{user_id}")
    :ok
  end

  # Private function to schedule next sync based on user presence
  defp schedule_next_adaptive_sync(user_id) do
    is_online = Agentleguide.Presence.user_online?(user_id)

    {interval, frequency_desc} =
      if is_online do
        {@online_interval, "5 seconds (user online)"}
      else
        {@offline_interval, "30 minutes (user offline)"}
      end

    Logger.debug("EmailSyncJob: Scheduling next sync in #{frequency_desc} for user #{user_id}")

    %{"user_id" => user_id, "adaptive" => true}
    |> __MODULE__.new(
      schedule_in: interval,
      unique: [period: 3, keys: [:user_id, :adaptive]]
    )
    |> Oban.insert()
  end
end

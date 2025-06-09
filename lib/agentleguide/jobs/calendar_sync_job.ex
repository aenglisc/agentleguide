defmodule Agentleguide.Jobs.CalendarSyncJob do
  @moduledoc """
  Background job for syncing Google Calendar events.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3
  require Logger

  alias Agentleguide.Accounts
  alias Agentleguide.Services.Google.CalendarService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    case Accounts.get_user(user_id) do
      nil ->
        Logger.warning("User not found for calendar sync: #{user_id}")
        {:error, "User not found"}

      user ->
        sync_calendar_events(user)
    end
  end

  @doc """
  Schedule a calendar sync job to run immediately.
  """
  def schedule_now(user_id) do
    %{user_id: user_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc """
  Schedule a calendar sync job to run at a specific time.
  """
  def schedule_at(user_id, scheduled_at) do
    %{user_id: user_id}
    |> __MODULE__.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  # Private functions

  defp sync_calendar_events(user) do
    case CalendarService.list_events(user) do
      {:ok, events} ->
        Logger.info("Successfully synced #{length(events)} calendar events for user #{user.id}")
        # In a real implementation, you'd store these events in the database
        # and potentially use them for RAG or proactive actions
        {:ok, "Calendar sync completed"}

      {:error, reason} ->
        Logger.error("Failed to sync calendar events for user #{user.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

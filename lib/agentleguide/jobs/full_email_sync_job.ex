defmodule Agentleguide.Jobs.HistoricalEmailSyncJob do
  @moduledoc """
  One-time job for performing a complete historical sync of all emails from Gmail.
  This runs once when a user connects to Google and pulls ALL emails in batches.
  Uses unique constraints to ensure only one instance runs per user.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Agentleguide.Services.Google.GmailService
  alias Agentleguide.Accounts
  require Logger

  @doc """
  Perform a complete historical email sync for a user.
  This will fetch ALL emails from Gmail, not just recent ones.
  Runs once when user connects to Google.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: nil}) do
    Logger.error("HistoricalEmailSyncJob: Job args cannot be nil")
    {:error, :nil_args}
  end

  def perform(%Oban.Job{args: args}) do
    user_id = args["user_id"]
    oldest_date = args["oldest_date"]
    total_synced = args["total_synced"] || 0
    page_token = args["page_token"]

    # Handle nil user_id or malformed user_id
    if is_nil(user_id) do
      Logger.error("HistoricalEmailSyncJob: Missing user_id in job args")
      {:error, :missing_user_id}
    else
      case safely_get_user(user_id) do
        {:ok, nil} ->
          Logger.error("HistoricalEmailSyncJob: User #{user_id} not found")
          {:error, :user_not_found}

        {:ok, user} ->
          if oldest_date do
            Logger.info(
              "Resuming historical email sync for user #{user.email} from #{oldest_date} (#{total_synced} emails synced so far)"
            )
          else
            Logger.info(
              "Starting historical email sync for user #{user.email}"
            )
          end

          case sync_emails_with_resume(user, oldest_date, total_synced, page_token) do
            {:ok, final_total} ->
              Logger.info(
                "HistoricalEmailSyncJob: Successfully synced #{final_total} historical emails for user #{user.email}"
              )

              # Mark historical sync as completed
              Agentleguide.Accounts.update_user(user, %{historical_email_sync_completed: true})
              :ok

            {:continue, new_args} ->
              # Schedule continuation job with updated progress
              Logger.info(
                "HistoricalEmailSyncJob: Scheduling continuation for user #{user.email} - #{new_args["total_synced"]} emails synced so far"
              )

              %{user_id: user_id}
              |> Map.merge(new_args)
              |> __MODULE__.new()
              |> Oban.insert()

              :ok

            {:error, reason} ->
              Logger.error(
                "HistoricalEmailSyncJob: Failed to sync emails for user #{user.email}: #{inspect(reason)}"
              )

              {:error, reason}
          end

        {:error, reason} ->
          Logger.error("HistoricalEmailSyncJob: Invalid user_id format: #{inspect(reason)}")
          {:error, :invalid_user_id}
      end
    end
  end

  @doc """
  Queue a one-time historical email sync job for a user.
  This should be called when the user first connects to Google.
  Uses unique constraints to prevent duplicate jobs.
  """
  def queue_historical_sync(user) do
    %{user_id: user.id}
    |> __MODULE__.new(unique: [period: 3600, fields: [:worker, :args]])
    |> Oban.insert()
  end

  # Sync emails with resume capability
  defp sync_emails_with_resume(user, oldest_date, total_synced, page_token) do
    # If we have an oldest_date, we're resuming - use it to build the query
    # Otherwise, start from the beginning (no date filter)
    query_params =
      if oldest_date do
        %{"maxResults" => "100", "pageToken" => page_token}
      else
        %{"maxResults" => "100"}
      end

    query_params =
      if page_token, do: Map.put(query_params, "pageToken", page_token), else: query_params

    sync_emails_batch_with_resume(user, oldest_date, total_synced, query_params, 0)
  end

  # Process emails in batches with resume capability
  # batch_count tracks how many batches we've processed in this job run
  defp sync_emails_batch_with_resume(user, oldest_date, total_synced, query_params, batch_count) do

    Logger.info(
      "HistoricalEmailSyncJob: Fetching batch #{batch_count + 1} for user #{user.email} (#{total_synced} synced so far)"
    )

    case GmailService.fetch_message_ids(user, query_params) do
      {:ok, %{message_ids: message_ids, next_page_token: next_token}} ->
        Logger.info("HistoricalEmailSyncJob: Got #{length(message_ids)} message IDs from Gmail")

        # Filter out emails we already have
        new_message_ids = filter_existing_message_ids(user, message_ids)

        Logger.info(
          "HistoricalEmailSyncJob: #{length(new_message_ids)} new emails to fetch and store"
        )

        # Fetch, parse, and store the new emails
        Logger.info(
          "HistoricalEmailSyncJob: Starting to fetch and store #{length(new_message_ids)} emails..."
        )

        case fetch_parse_and_store_emails(user, new_message_ids) do
          {:ok, results} ->
            Logger.info("HistoricalEmailSyncJob: Completed fetching and storing emails")

            batch_synced = length(new_message_ids)
            new_total = total_synced + batch_synced

            # Track the oldest email date from this batch for resume capability
            new_oldest_date =
              if length(results) > 0 do
                results
                |> Enum.map(fn {:ok, email} -> email.date end)
                |> Enum.filter(& &1)
                |> Enum.min(DateTime, fn -> oldest_date end)
              else
                oldest_date
              end

            Logger.info(
              "HistoricalEmailSyncJob: Synced batch of #{batch_synced} emails (total: #{new_total}) for user #{user.email}"
            )

            # Every 10 batches or if we have a next token, save progress and continue in a new job
            # This prevents jobs from running too long and allows for better error recovery
            if next_token && (batch_count >= 9 || rem(new_total, 1000) == 0) do
              resume_args = %{
                "oldest_date" => new_oldest_date && DateTime.to_iso8601(new_oldest_date),
                "total_synced" => new_total,
                "page_token" => next_token
              }

              {:continue, resume_args}
            else
              # Continue in the same job
              if next_token do
                # Add a small delay to avoid hitting API rate limits
                Process.sleep(100)
                new_query_params = Map.put(query_params, "pageToken", next_token)

                sync_emails_batch_with_resume(
                  user,
                  new_oldest_date,
                  new_total,
                  new_query_params,
                  batch_count + 1
                )
              else
                {:ok, new_total}
              end
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{message_ids: []}} ->
        # No more emails
        {:ok, total_synced}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fetch, parse, and store emails using the new separated service methods
  defp fetch_parse_and_store_emails(user, message_ids) do
    with {:ok, %{successes: message_data_list}} <- GmailService.fetch_messages(user, message_ids),
         parsed_emails <- Enum.map(message_data_list, fn {:ok, data} -> GmailService.parse_message(data) end),
         {:ok, %{successes: stored_emails}} <- GmailService.store_emails(user, parsed_emails) do
      {:ok, stored_emails}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Filter out message IDs that already exist in our database
  defp filter_existing_message_ids(user, message_ids) do
    existing_ids = Agentleguide.Rag.get_existing_gmail_ids(user, message_ids)
    message_ids -- existing_ids
  end

  # Safely get user, handling malformed UUID gracefully
  defp safely_get_user(user_id) do
    try do
      {:ok, Accounts.get_user(user_id)}
    rescue
      Ecto.Query.CastError ->
        {:error, :invalid_uuid}
    end
  end
end

defmodule Agentleguide.Jobs.HistoricalEmailSyncJob do
  @moduledoc """
  One-time job for performing a historical sync of recent emails from Gmail.
  This runs once when a user connects to Google and pulls up to #{@max_historical_emails} recent emails in batches.
  Uses unique constraints to ensure only one instance runs per user.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Agentleguide.Services.Google.GmailService
  alias Agentleguide.Accounts
  require Logger

  # Maximum number of emails to sync during historical sync
  @max_historical_emails 200

  @doc """
  Perform a historical email sync for a user.
  This will fetch up to 200 recent emails from Gmail.
  Runs once when user connects to Google.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    user_id = args["user_id"]
    oldest_date = args["oldest_date"]
    total_synced = args["total_synced"] || 0
    page_token = args["page_token"]

    case Accounts.get_user(user_id) do
      nil ->
        Logger.error("HistoricalEmailSyncJob: User #{user_id} not found")
        {:error, :user_not_found}

      user ->
        if oldest_date do
          Logger.info(
            "HistoricalEmailSyncJob: Resuming historical email sync for user #{user.email} from #{oldest_date} (#{total_synced} emails synced so far)"
          )
        else
          Logger.info(
            "HistoricalEmailSyncJob: Starting historical email sync for user #{user.email}"
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
    # Check if we've reached the email limit
    if total_synced >= @max_historical_emails do
      Logger.info(
        "HistoricalEmailSyncJob: Reached #{@max_historical_emails} email limit for user #{user.email} (#{total_synced} emails synced)"
      )

      {:ok, total_synced}
    else
      Logger.info(
        "HistoricalEmailSyncJob: Fetching batch #{batch_count + 1} for user #{user.email} (#{total_synced} synced so far, limit: #{@max_historical_emails})"
      )

      case fetch_email_batch(user, query_params["pageToken"]) do
        {:ok, %{message_ids: message_ids, next_page_token: next_token}} ->
          Logger.info("HistoricalEmailSyncJob: Got #{length(message_ids)} message IDs from Gmail")

          # Filter out emails we already have
          new_message_ids = filter_existing_message_ids(user, message_ids)

          # Limit the batch to not exceed maximum total emails
          remaining_limit = @max_historical_emails - total_synced
          limited_message_ids = Enum.take(new_message_ids, remaining_limit)

          Logger.info(
            "HistoricalEmailSyncJob: #{length(limited_message_ids)} new emails to fetch and store (limited to #{remaining_limit} remaining)"
          )

          # Fetch and store the new emails
          Logger.info(
            "HistoricalEmailSyncJob: Starting to fetch and store #{length(limited_message_ids)} emails..."
          )

          {:ok, results} = GmailService.fetch_and_store_messages(user, limited_message_ids)
          Logger.info("HistoricalEmailSyncJob: Completed fetching and storing emails")

          batch_synced = length(limited_message_ids)
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
            "HistoricalEmailSyncJob: Synced batch of #{batch_synced} emails (total: #{new_total}/#{@max_historical_emails}) for user #{user.email}"
          )

          # Check if we've reached the limit or there are no more emails
          if new_total >= @max_historical_emails do
            Logger.info(
              "HistoricalEmailSyncJob: Reached #{@max_historical_emails} email limit for user #{user.email} (#{new_total} emails synced)"
            )

            {:ok, new_total}
          else
            # Continue if we haven't reached the limit and there are more emails
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

        {:ok, %{message_ids: []}} ->
          # No more emails
          {:ok, total_synced}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Fetch a batch of email IDs from Gmail
  defp fetch_email_batch(user, page_token) do
    base_url = "https://gmail.googleapis.com/gmail/v1/users/me/messages"

    # Build query parameters
    params = %{"maxResults" => "100"}
    params = if page_token, do: Map.put(params, "pageToken", page_token), else: params

    query_string = URI.encode_query(params)
    url = "#{base_url}?#{query_string}"

    headers = [{"Authorization", "Bearer #{user.google_access_token}"}]

    case Finch.build(:get, url, headers)
         |> Finch.request(Agentleguide.Finch, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"messages" => messages} = response} ->
            message_ids = Enum.map(messages, & &1["id"])
            next_page_token = response["nextPageToken"]

            {:ok, %{message_ids: message_ids, next_page_token: next_page_token}}

          {:ok, %{}} ->
            # No messages
            {:ok, %{message_ids: [], next_page_token: nil}}

          {:error, error} ->
            Logger.error(
              "HistoricalEmailSyncJob: Failed to parse Gmail response: #{inspect(error)}"
            )

            {:error, error}
        end

      {:ok, %{status: 401}} ->
        Logger.error(
          "HistoricalEmailSyncJob: Gmail API authentication failed for user #{user.id}"
        )

        {:error, :auth_failed}

      {:ok, %{status: status, body: body}} ->
        Logger.error("HistoricalEmailSyncJob: Gmail API error #{status}: #{body}")
        {:error, {:api_error, status}}

      {:error, error} ->
        Logger.error("HistoricalEmailSyncJob: Network error: #{inspect(error)}")
        {:error, error}
    end
  end

  # Filter out message IDs that already exist in our database
  defp filter_existing_message_ids(user, message_ids) do
    existing_ids = Agentleguide.Rag.get_existing_gmail_ids(user, message_ids)
    message_ids -- existing_ids
  end
end

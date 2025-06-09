defmodule Agentleguide.Services.Google.GmailService do
  @moduledoc """
  Service for interacting with Gmail API to fetch and sync user emails.
  """



  require Logger
  alias Agentleguide.Rag

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1"

  @doc """
  Sync recent emails for a user (incremental sync).
  Only fetches emails newer than the last synced email.
  """
  def sync_recent_emails(user) do
    last_sync_time = get_last_sync_time(user)

    with {:ok, message_ids} <- list_new_message_ids(user, last_sync_time),
         {:ok, _results} <- fetch_and_store_messages(user, message_ids) do
      # Update user's last sync time
      update_user_sync_time(user)
      # Return count for job logging, but don't log here to avoid duplicates
      {:ok, length(message_ids)}
    else
      {:error, reason} ->
        # Only log errors at debug level since the job will log them properly
        Logger.debug("Gmail sync error for user #{user.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get the last sync time for a user (either last email date or gmail_connected_at).
  defp get_last_sync_time(user) do
    latest_email = Rag.get_latest_gmail_email(user)

    case latest_email do
      nil ->
        # If no emails exist, use connection time or default to 30 days ago
        user.gmail_connected_at || DateTime.add(DateTime.utc_now(), -30, :day)

      email ->
        # Use the date of the most recent email
        email.date || email.inserted_at
    end
  end

  # List only NEW message IDs from Gmail since the last sync.
  defp list_new_message_ids(user, since_datetime) do
    # Convert datetime to Gmail search format (YYYY/MM/DD)
    since_date = DateTime.to_date(since_datetime)
    query = "after:#{since_date}"

    url = "#{@gmail_api_base}/users/me/messages?q=#{URI.encode(query)}&maxResults=100"

    case make_gmail_request(user, url) do
      {:ok, %{"messages" => messages}} ->
        message_ids = Enum.map(messages, & &1["id"])
        # Filter out emails we already have in our database
        new_message_ids = filter_existing_message_ids(user, message_ids)
        {:ok, new_message_ids}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Filter out message IDs that already exist in our database.
  defp filter_existing_message_ids(user, message_ids) do
    existing_ids = Rag.get_existing_gmail_ids(user, message_ids)
    message_ids -- existing_ids
  end

  # Update the user's last Gmail sync time.
  defp update_user_sync_time(user) do
    Agentleguide.Accounts.update_user(user, %{gmail_last_synced_at: DateTime.utc_now()})
  end

  @doc """
  List recent message IDs from Gmail (last 30 days) - DEPRECATED.
  Use list_new_message_ids/2 instead for incremental sync.
  """
  def list_recent_message_ids(user) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
    query = "after:#{DateTime.to_date(thirty_days_ago)}"

    url = "#{@gmail_api_base}/users/me/messages?q=#{URI.encode(query)}&maxResults=50"

    case make_gmail_request(user, url) do
      {:ok, %{"messages" => messages}} ->
        message_ids = Enum.map(messages, & &1["id"])
        {:ok, message_ids}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch message IDs from Gmail for a date range.
  Returns raw message IDs without any database operations.
  """
  def fetch_message_ids(user, query_params \\ %{}) do
    base_url = "#{@gmail_api_base}/users/me/messages"

    # Default parameters
    params = Map.merge(%{"maxResults" => "100"}, query_params)

    query_string = URI.encode_query(params)
    url = "#{base_url}?#{query_string}"

    case make_gmail_request(user, url) do
      {:ok, %{"messages" => messages} = response} ->
        message_ids = Enum.map(messages, & &1["id"])
        next_page_token = response["nextPageToken"]
        {:ok, %{message_ids: message_ids, next_page_token: next_page_token}}

      {:ok, %{}} ->
        {:ok, %{message_ids: [], next_page_token: nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch individual messages by their IDs.
  Returns raw message data without storing anything.
  """
  def fetch_messages(user, message_ids) do
    results =
      Enum.map(message_ids, fn message_id ->
        case fetch_message(user, message_id) do
          {:ok, message_data} ->
            {:ok, message_data}

          {:error, reason} ->
            Logger.warning("Failed to fetch message #{message_id}: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    {:ok, %{successes: successes, errors: errors}}
  end

  @doc """
  Fetch a single message by ID.
  Returns raw message data without storing anything.
  """
  def fetch_message(user, message_id) do
    url = "#{@gmail_api_base}/users/me/messages/#{message_id}?format=full"

    case make_gmail_request(user, url) do
      {:ok, message_data} ->
        {:ok, message_data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Parse raw Gmail message data into a structured format.
  Pure function that doesn't touch the database.
  """
  def parse_message(message_data) do
    gmail_id = message_data["id"]
    thread_id = message_data["threadId"]

    # Parse headers
    headers = get_in(message_data, ["payload", "headers"]) || []

    headers_map =
      Enum.into(headers, %{}, fn %{"name" => name, "value" => value} ->
        {String.downcase(name), value}
      end)

    subject = headers_map["subject"] || ""
    from = headers_map["from"] || ""
    to = headers_map["to"] || ""
    date = headers_map["date"] || ""

    # Parse from email and name
    {from_email, from_name} = parse_email_address(from)

    # Parse to emails (can be multiple)
    to_emails = if to != "", do: [to], else: []

    # Extract email body
    body_text = extract_email_body(message_data["payload"])

    # Parse labels
    label_ids = message_data["labelIds"] || []

    %{
      gmail_id: gmail_id,
      thread_id: thread_id,
      subject: subject,
      from_email: from_email,
      from_name: from_name,
      to_emails: to_emails,
      body_text: body_text,
      labels: label_ids,
      date: parse_email_date(date),
      last_synced_at: DateTime.utc_now()
    }
  end

  @doc """
  Store parsed email data to the database.
  Separate from fetching operations.
  """
  def store_emails(user, parsed_emails) do
    results =
      Enum.map(parsed_emails, fn email_attrs ->
        case Rag.upsert_gmail_email(user, email_attrs) do
          {:ok, email} ->
            # Queue embedding generation as a background job (unless disabled in tests)
            if should_queue_embeddings?() do
              %{user_id: user.id, email_id: email.id}
              |> Agentleguide.Jobs.EmbeddingJob.new()
              |> Oban.insert()
            end

            {:ok, email}

          {:error, reason} ->
            {:error, reason}
        end
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, _}, &1))

    if length(errors) > 0 do
      {:error, {:partial_failure, %{successes: successes, errors: errors}}}
    else
      {:ok, %{successes: successes, errors: errors}}
    end
  end

  @doc """
  Legacy method for backwards compatibility.
  Now orchestrates fetch, parse, and store operations.
  """
  def fetch_and_store_messages(user, message_ids) do
    with {:ok, %{successes: message_data_list}} <- fetch_messages(user, message_ids) do
      parsed_emails =
        message_data_list
        |> Enum.map(fn {:ok, message_data} -> parse_message(message_data) end)

      case store_emails(user, parsed_emails) do
        {:ok, %{successes: successes}} -> {:ok, successes}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Legacy method for backwards compatibility.
  """
  def fetch_and_store_message(user, message_id) do
    case fetch_and_store_messages(user, [message_id]) do
      {:ok, [result]} -> result
      {:ok, []} -> {:error, :no_results}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_email_body(payload) do
    cond do
      # Simple text email
      payload["body"]["data"] ->
        decode_base64_body(payload["body"]["data"])

      # Multipart email
      payload["parts"] ->
        extract_from_parts(payload["parts"])

      true ->
        ""
    end
  end

  defp extract_from_parts(parts) do
    # Find text/plain part first, fall back to text/html
    text_part =
      Enum.find(parts, fn part ->
        get_in(part, ["mimeType"]) == "text/plain"
      end)

    html_part =
      Enum.find(parts, fn part ->
        get_in(part, ["mimeType"]) == "text/html"
      end)

    part_to_use = text_part || html_part

    case part_to_use do
      %{"body" => %{"data" => data}} ->
        decode_base64_body(data)

      %{"parts" => nested_parts} ->
        extract_from_parts(nested_parts)

      _ ->
        ""
    end
  end

  defp decode_base64_body(encoded_data) do
    try do
      encoded_data
      |> String.replace("-", "+")
      |> String.replace("_", "/")
      |> Base.decode64!(padding: false)
    rescue
      _ -> ""
    end
  end

  defp parse_email_address(email_string) do
    case Regex.run(~r/^(.+?)\s*<(.+)>$/, String.trim(email_string)) do
      [_, name, email] ->
        {String.trim(email), String.trim(name, ~s("'))}

      _ ->
        email = String.trim(email_string)
        {email, email}
    end
  end

  defp parse_email_date(_date_string) do
    # Gmail date parsing is complex, for now just use current time
    # In production, you'd want proper RFC 2822 date parsing
    DateTime.utc_now()
  end

  @doc """
  Send an email via Gmail API.
  """
  def send_email(user, to_email, subject, body) do
    url = "#{@gmail_api_base}/users/me/messages/send"

    # Create the email message
    email_content = create_email_message(user.email, to_email, subject, body)

    # Encode the message
    encoded_message =
      Base.encode64(email_content, padding: false)
      |> String.replace("+", "-")
      |> String.replace("/", "_")

    request_body = %{
      "raw" => encoded_message
    }

    case make_gmail_request(user, url, :post, request_body) do
      {:ok, response} ->
        Logger.info("Successfully sent email to #{to_email} for user #{user.id}")
        {:ok, response}

      {:error, reason} ->
        Logger.error(
          "Failed to send email to #{to_email} for user #{user.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp create_email_message(from_email, to_email, subject, body) do
    """
    From: #{from_email}
    To: #{to_email}
    Subject: #{subject}
    Content-Type: text/plain; charset=utf-8

    #{body}
    """
  end

  defp make_gmail_request(user, url, method \\ :get, body \\ nil) do
    headers = [
      {"Authorization", "Bearer #{user.google_access_token}"},
      {"Content-Type", "application/json"}
    ]

    request =
      case method do
        :get -> http_client().build(:get, url, headers, nil)
        :post -> http_client().build(:post, url, headers, Jason.encode!(body))
        :put -> http_client().build(:put, url, headers, Jason.encode!(body))
        :delete -> http_client().build(:delete, url, headers, nil)
      end

    case http_client().request(request, Agentleguide.Finch) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        case Jason.decode(response_body) do
          {:ok, data} -> {:ok, data}
          {:error, error} -> {:error, {:json_decode_error, error}}
        end

      {:ok, %{status: 401}} ->
        Logger.error("Gmail API authentication failed for user #{user.id}")
        {:error, :auth_failed}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("Gmail API error #{status}: #{response_body}")
        {:error, {:api_error, status, response_body}}

      {:error, error} ->
        Logger.error("Gmail API request failed: #{inspect(error)}")
        {:error, {:request_failed, error}}
    end
  end

  defp http_client do
    Application.get_env(:agentleguide, :gmail_http_client, Finch)
  end

  # Allow embedding job queueing to be configurable for testing
  defp should_queue_embeddings? do
    Application.get_env(:agentleguide, :queue_embeddings, true)
  end
end

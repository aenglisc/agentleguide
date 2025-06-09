defmodule Agentleguide.Services.Google.GmailService do
  @moduledoc """
  Service for interacting with Gmail API to fetch and sync user emails.
  """

  require Logger

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
    latest_email = Agentleguide.Rag.get_latest_gmail_email(user)

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
    existing_ids = Agentleguide.Rag.get_existing_gmail_ids(user, message_ids)
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
  Fetch and store individual messages.
  """
  def fetch_and_store_messages(user, message_ids) do
    results =
      Enum.map(message_ids, fn message_id ->
        case fetch_and_store_message(user, message_id) do
          {:ok, email} ->
            {:ok, email}

          {:error, reason} ->
            Logger.warning("Failed to fetch message #{message_id}: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    {:ok, successes}
  end

  @doc """
  Fetch a single message and store it.
  """
  def fetch_and_store_message(user, message_id) do
    url = "#{@gmail_api_base}/users/me/messages/#{message_id}?format=full"

    case make_gmail_request(user, url) do
      {:ok, message_data} ->
        case parse_and_store_message(user, message_data) do
          {:ok, email} ->
            # Queue embedding generation as a background job
            %{user_id: user.id, email_id: email.id}
            |> Agentleguide.Jobs.EmbeddingJob.new()
            |> Oban.insert()

            {:ok, email}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_and_store_message(user, message_data) do
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

    email_attrs = %{
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

    Agentleguide.Rag.upsert_gmail_email(user, email_attrs)
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

  defp parse_email_date(date_string) when is_binary(date_string) and date_string != "" do
    # Try to parse RFC 2822 date format used by Gmail
    # Examples: "Thu, 13 Feb 2020 15:02:01 +0000" or "Mon, 1 Jan 2024 10:30:00 -0500"

    # Remove any extra whitespace and normalize
    normalized_date = String.trim(date_string)

    # Try different parsing approaches
    case parse_rfc2822_date(normalized_date) do
      {:ok, datetime} ->
        datetime

      {:error, _reason} ->
        # Fallback: try a simpler parse for malformed dates
        case parse_simple_date(normalized_date) do
          {:ok, datetime} ->
            datetime

          {:error, _reason} ->
            # Last resort: use current time but log the issue
            Logger.warning(
              "Failed to parse email date: #{inspect(date_string)}, using current time"
            )

            DateTime.utc_now()
        end
    end
  end

  defp parse_email_date(_date_string) do
    # Empty or invalid date string
    DateTime.utc_now()
  end

  # Parse RFC 2822 date format
  defp parse_rfc2822_date(date_string) do
    # Remove day name if present (e.g., "Thu, ")
    date_without_day = Regex.replace(~r/^[A-Za-z]{3},\s*/, date_string, "")

    # Try to parse with Elixir's built-in parsing
    case DateTime.from_iso8601(convert_rfc2822_to_iso8601(date_without_day)) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :parse_failed}
  end

  # Convert RFC 2822 format to ISO 8601 for Elixir parsing
  defp convert_rfc2822_to_iso8601(date_string) do
    # Handle formats like "13 Feb 2020 15:02:01 +0000"
    # Convert month names to numbers
    month_map = %{
      "Jan" => "01",
      "Feb" => "02",
      "Mar" => "03",
      "Apr" => "04",
      "May" => "05",
      "Jun" => "06",
      "Jul" => "07",
      "Aug" => "08",
      "Sep" => "09",
      "Oct" => "10",
      "Nov" => "11",
      "Dec" => "12"
    }

    # Pattern: "13 Feb 2020 15:02:01 +0000"
    pattern = ~r/(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s*([\+\-]\d{4})/

    case Regex.run(pattern, date_string) do
      [_, day, month_name, year, hour, minute, second, timezone] ->
        month = Map.get(month_map, month_name, "01")
        # Pad day with leading zero if needed
        day = String.pad_leading(day, 2, "0")
        # Convert timezone format from +0000 to +00:00
        tz = String.slice(timezone, 0, 3) <> ":" <> String.slice(timezone, 3, 2)

        "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}#{tz}"

      nil ->
        raise "Could not parse RFC 2822 date format"
    end
  end

  # Simple fallback date parsing for malformed dates
  defp parse_simple_date(date_string) do
    # Try to extract basic date components and build a reasonable datetime
    # This is a fallback for really malformed dates

    # Look for year first (4 digits)
    year_match = Regex.run(~r/(\d{4})/, date_string)

    case year_match do
      [_, year] ->
        # Use a reasonable default date with the extracted year
        case Date.new(String.to_integer(year), 1, 1) do
          {:ok, date} ->
            {:ok, DateTime.new!(date, ~T[00:00:00])}

          _ ->
            {:error, :invalid_year}
        end

      nil ->
        {:error, :no_year_found}
    end
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
        :get -> Finch.build(:get, url, headers)
        :post -> Finch.build(:post, url, headers, Jason.encode!(body))
        :put -> Finch.build(:put, url, headers, Jason.encode!(body))
        :delete -> Finch.build(:delete, url, headers)
      end

    case Finch.request(request, Agentleguide.Finch) do
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
end

defmodule Agentleguide.CalendarService do
  @moduledoc """
  Service for interacting with Google Calendar API to manage events and scheduling.
  """

  require Logger

  @calendar_api_base "https://www.googleapis.com/calendar/v3"

  @doc """
  Get available time slots for a user within a date range.
  """
  def get_available_slots(user, start_date, end_date, duration_minutes \\ 60) do
    with {:ok, events} <- fetch_events(user, start_date, end_date),
         available_slots <-
           calculate_available_slots(events, start_date, end_date, duration_minutes) do
      {:ok, available_slots}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetch events from Google Calendar for a date range.
  """
  def fetch_events(user, start_date, end_date) do
    start_time = DateTime.to_iso8601(start_date)
    end_time = DateTime.to_iso8601(end_date)

    url =
      "#{@calendar_api_base}/calendars/primary/events?timeMin=#{start_time}&timeMax=#{end_time}&singleEvents=true&orderBy=startTime"

    case make_calendar_request(user, url) do
      {:ok, %{"items" => events}} ->
        {:ok, events}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a new calendar event.
  """
  def create_event(user, event_attrs) do
    url = "#{@calendar_api_base}/calendars/primary/events"

    event_body = %{
      "summary" => event_attrs[:title] || event_attrs[:summary],
      "description" => event_attrs[:description],
      "start" => %{
        "dateTime" => DateTime.to_iso8601(event_attrs[:start_time]),
        "timeZone" => event_attrs[:timezone] || "UTC"
      },
      "end" => %{
        "dateTime" => DateTime.to_iso8601(event_attrs[:end_time]),
        "timeZone" => event_attrs[:timezone] || "UTC"
      },
      "attendees" => format_attendees(event_attrs[:attendees] || [])
    }

    case make_calendar_request(user, url, :post, event_body) do
      {:ok, event_data} ->
        Logger.info("Created calendar event: #{event_data["id"]} for user #{user.id}")
        {:ok, event_data}

      {:error, reason} ->
        Logger.error("Failed to create calendar event for user #{user.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Update an existing calendar event.
  """
  def update_event(user, event_id, event_attrs) do
    url = "#{@calendar_api_base}/calendars/primary/events/#{event_id}"

    event_body = %{
      "summary" => event_attrs[:title] || event_attrs[:summary],
      "description" => event_attrs[:description],
      "start" => %{
        "dateTime" => DateTime.to_iso8601(event_attrs[:start_time]),
        "timeZone" => event_attrs[:timezone] || "UTC"
      },
      "end" => %{
        "dateTime" => DateTime.to_iso8601(event_attrs[:end_time]),
        "timeZone" => event_attrs[:timezone] || "UTC"
      },
      "attendees" => format_attendees(event_attrs[:attendees] || [])
    }

    case make_calendar_request(user, url, :put, event_body) do
      {:ok, event_data} ->
        Logger.info("Updated calendar event: #{event_data["id"]} for user #{user.id}")
        {:ok, event_data}

      {:error, reason} ->
        Logger.error(
          "Failed to update calendar event #{event_id} for user #{user.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Delete a calendar event.
  """
  def delete_event(user, event_id) do
    url = "#{@calendar_api_base}/calendars/primary/events/#{event_id}"

    case make_calendar_request(user, url, :delete) do
      {:ok, _} ->
        Logger.info("Deleted calendar event: #{event_id} for user #{user.id}")
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to delete calendar event #{event_id} for user #{user.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Find upcoming events for a user (next 7 days).
  """
  def get_upcoming_events(user, days \\ 7) do
    start_date = DateTime.utc_now()
    end_date = DateTime.add(start_date, days * 24 * 60 * 60, :second)

    fetch_events(user, start_date, end_date)
  end

  defp calculate_available_slots(events, start_date, end_date, duration_minutes) do
    # Convert events to busy periods
    busy_periods =
      Enum.map(events, fn event ->
        start_time = parse_event_time(event["start"])
        end_time = parse_event_time(event["end"])
        {start_time, end_time}
      end)
      |> Enum.filter(fn {start_time, end_time} -> start_time && end_time end)
      |> Enum.sort()

    # Generate available slots (simplified - assumes 9 AM to 5 PM working hours)
    generate_working_hour_slots(start_date, end_date, busy_periods, duration_minutes)
  end

  defp generate_working_hour_slots(start_date, end_date, busy_periods, duration_minutes) do
    # This is a simplified implementation
    # In a real app, you'd want to consider user's working hours, timezone, etc.

    current_date = DateTime.to_date(start_date)
    end_date_only = DateTime.to_date(end_date)

    Stream.unfold(current_date, fn date ->
      if Date.compare(date, end_date_only) == :lt do
        slots = generate_daily_slots(date, busy_periods, duration_minutes)
        {slots, Date.add(date, 1)}
      else
        nil
      end
    end)
    |> Enum.to_list()
    |> List.flatten()
  end

  defp generate_daily_slots(date, busy_periods, duration_minutes) do
    # Generate slots from 9 AM to 5 PM
    start_time = DateTime.new!(date, ~T[09:00:00], "UTC")
    end_time = DateTime.new!(date, ~T[17:00:00], "UTC")

    # Convert to seconds
    slot_duration = duration_minutes * 60

    Stream.unfold(start_time, fn current_time ->
      slot_end = DateTime.add(current_time, slot_duration, :second)

      if DateTime.compare(slot_end, end_time) != :gt do
        # Check if this slot conflicts with any busy period
        conflicts =
          Enum.any?(busy_periods, fn {busy_start, busy_end} ->
            DateTime.compare(current_time, busy_end) == :lt and
              DateTime.compare(slot_end, busy_start) == :gt
          end)

        if conflicts do
          # Skip 30 minutes
          {nil, DateTime.add(current_time, 30 * 60, :second)}
        else
          slot = %{
            start_time: current_time,
            end_time: slot_end,
            duration_minutes: duration_minutes
          }

          # 30-minute intervals
          {slot, DateTime.add(current_time, 30 * 60, :second)}
        end
      else
        nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.to_list()
  end

  defp parse_event_time(%{"dateTime" => date_time}) do
    case DateTime.from_iso8601(date_time) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_event_time(%{"date" => date}) do
    # All-day event
    case Date.from_iso8601(date) do
      {:ok, d} -> DateTime.new!(d, ~T[00:00:00], "UTC")
      _ -> nil
    end
  end

  defp parse_event_time(_), do: nil

  defp format_attendees(attendees) when is_list(attendees) do
    Enum.map(attendees, fn
      email when is_binary(email) -> %{"email" => email}
      %{email: email} -> %{"email" => email}
      %{"email" => email} -> %{"email" => email}
      attendee -> attendee
    end)
  end

  defp format_attendees(_), do: []

  defp make_calendar_request(user, url, method \\ :get, body \\ nil) do
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
        if response_body == "" do
          {:ok, %{}}
        else
          case Jason.decode(response_body) do
            {:ok, data} -> {:ok, data}
            {:error, error} -> {:error, {:json_decode_error, error}}
          end
        end

      {:ok, %{status: 401}} ->
        Logger.error("Google Calendar API authentication failed for user #{user.id}")
        {:error, :auth_failed}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("Google Calendar API error #{status}: #{response_body}")
        {:error, {:api_error, status, response_body}}

      {:error, error} ->
        Logger.error("Google Calendar API request failed: #{inspect(error)}")
        {:error, {:request_failed, error}}
    end
  end
end

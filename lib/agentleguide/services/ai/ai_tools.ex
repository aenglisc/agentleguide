defmodule Agentleguide.Services.Ai.AiTools do
  @moduledoc """
  Tool calling system for the AI agent.
  Provides functions for email, calendar, and HubSpot operations.
  """

  require Logger

  @doc """
  Get available tools for the AI agent.
  """
  def get_available_tools do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_contacts",
          "description" =>
            "Search for contacts in HubSpot CRM by name, email, or company. If no query is provided, returns all contacts.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{
                "type" => "string",
                "description" =>
                  "Search query for contact name, email, or company. Optional - if not provided, returns all contacts."
              }
            },
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_emails",
          "description" =>
            "Search through Gmail emails by content, sender, subject, or keywords. Use this for finding specific emails or checking for new mail from someone.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{
                "type" => "string",
                "description" =>
                  "Search query for email content, sender name/email, subject, or keywords like 'golf', 'meeting', etc."
              },
              "sender" => %{
                "type" => "string",
                "description" => "Filter by sender email or name (optional)"
              },
              "limit" => %{
                "type" => "integer",
                "description" => "Maximum number of emails to return (default: 10)"
              }
            },
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "send_email",
          "description" => "Send an email to a contact",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "to_email" => %{
                "type" => "string",
                "description" => "Recipient email address"
              },
              "subject" => %{
                "type" => "string",
                "description" => "Email subject line"
              },
              "body" => %{
                "type" => "string",
                "description" => "Email body content"
              }
            },
            "required" => ["to_email", "subject", "body"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_available_time_slots",
          "description" => "Get available time slots for scheduling meetings",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "start_date" => %{
                "type" => "string",
                "description" => "Start date for availability search (YYYY-MM-DD format)"
              },
              "end_date" => %{
                "type" => "string",
                "description" => "End date for availability search (YYYY-MM-DD format)"
              },
              "duration_minutes" => %{
                "type" => "integer",
                "description" => "Meeting duration in minutes (default: 60)"
              }
            },
            "required" => ["start_date", "end_date"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "schedule_meeting",
          "description" => "Schedule a meeting with a contact",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "title" => %{
                "type" => "string",
                "description" => "Meeting title"
              },
              "start_time" => %{
                "type" => "string",
                "description" => "Meeting start time (ISO 8601 format)"
              },
              "end_time" => %{
                "type" => "string",
                "description" => "Meeting end time (ISO 8601 format)"
              },
              "attendee_emails" => %{
                "type" => "array",
                "items" => %{"type" => "string"},
                "description" => "List of attendee email addresses"
              },
              "description" => %{
                "type" => "string",
                "description" => "Meeting description"
              }
            },
            "required" => ["title", "start_time", "end_time", "attendee_emails"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_hubspot_contact",
          "description" => "Create a new contact in HubSpot CRM",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "email" => %{
                "type" => "string",
                "description" => "Contact email address"
              },
              "first_name" => %{
                "type" => "string",
                "description" => "Contact first name"
              },
              "last_name" => %{
                "type" => "string",
                "description" => "Contact last name"
              },
              "company" => %{
                "type" => "string",
                "description" => "Contact company name"
              },
              "phone" => %{
                "type" => "string",
                "description" => "Contact phone number"
              }
            },
            "required" => ["email"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_upcoming_events",
          "description" => "Get upcoming calendar events",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "days" => %{
                "type" => "integer",
                "description" => "Number of days to look ahead (default: 7)"
              }
            }
          }
        }
      }
    ]
  end

  @doc """
  Execute a tool call.
  """
  def execute_tool_call(user, tool_name, arguments) do
    case tool_name do
      "search_contacts" ->
        search_contacts(user, arguments)

      "search_emails" ->
        search_emails(user, arguments)

      "send_email" ->
        send_email(user, arguments)

      "get_available_time_slots" ->
        get_available_time_slots(user, arguments)

      "schedule_meeting" ->
        schedule_meeting(user, arguments)

      "create_hubspot_contact" ->
        create_hubspot_contact(user, arguments)

      "get_upcoming_events" ->
        get_upcoming_events(user, arguments)

      _ ->
        {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Tool implementations

  defp search_contacts(user, arguments) do
    # Handle both search with query and list all contacts
    contacts =
      case arguments do
        %{"query" => query} when query != "" ->
          Agentleguide.Rag.search_contacts(user, query)

        _ ->
          # If no query provided, list all contacts
          Agentleguide.Rag.list_hubspot_contacts(user)
      end

    formatted_contacts =
      Enum.map(contacts, fn contact ->
        %{
          "id" => contact.id,
          "name" => Agentleguide.Rag.HubspotContact.display_name(contact),
          "email" => contact.email,
          "company" => contact.company,
          "phone" => contact.phone
        }
      end)

    {:ok, %{"contacts" => formatted_contacts, "count" => length(formatted_contacts)}}
  end

  defp search_emails(user, arguments) do
    query = arguments["query"] || ""
    sender = arguments["sender"]
    limit = arguments["limit"] || 10

    # Search emails using the RAG system
    emails =
      if sender do
        # If sender is specified, search by sender and optionally query
        Agentleguide.Rag.search_emails_by_sender(user, sender, query, limit)
      else
        # General email search
        if query != "" do
          Agentleguide.Rag.search_emails(user, query, limit)
        else
          # If no query, get recent emails
          Agentleguide.Rag.get_recent_emails(user, limit)
        end
      end

    formatted_emails =
      Enum.map(emails, fn email ->
        %{
          "id" => email.id,
          "subject" => email.subject || "No Subject",
          "from_name" => email.from_name || email.from_email,
          "from_email" => email.from_email,
          "date" => if(email.date, do: DateTime.to_iso8601(email.date), else: nil),
          "snippet" => String.slice(email.body_text || "", 0, 150)
        }
      end)

    {:ok, %{"emails" => formatted_emails, "count" => length(formatted_emails)}}
  end

  defp send_email(user, %{"to_email" => to_email, "subject" => subject, "body" => body}) do
          case Agentleguide.Services.Google.GmailService.send_email(user, to_email, subject, body) do
      {:ok, _response} ->
        {:ok, %{"status" => "sent", "message" => "Email sent successfully to #{to_email}"}}

      {:error, reason} ->
        {:error, "Failed to send email: #{inspect(reason)}"}
    end
  end

  defp get_available_time_slots(user, arguments) do
    start_date = parse_date(arguments["start_date"])
    end_date = parse_date(arguments["end_date"])
    duration_minutes = arguments["duration_minutes"] || 60

    case {start_date, end_date} do
      {{:ok, start_dt}, {:ok, end_dt}} ->
        case Agentleguide.Services.Google.CalendarService.get_available_slots(
               user,
               start_dt,
               end_dt,
               duration_minutes
             ) do
          {:ok, slots} ->
            formatted_slots =
              Enum.map(slots, fn slot ->
                %{
                  "start_time" => DateTime.to_iso8601(slot.start_time),
                  "end_time" => DateTime.to_iso8601(slot.end_time),
                  "duration_minutes" => slot.duration_minutes
                }
              end)

            {:ok, %{"available_slots" => formatted_slots, "count" => length(formatted_slots)}}

          {:error, reason} ->
            {:error, "Failed to get available slots: #{inspect(reason)}"}
        end

      _ ->
        {:error, "Invalid date format. Use YYYY-MM-DD format."}
    end
  end

  defp schedule_meeting(user, arguments) do
    %{
      "title" => title,
      "start_time" => start_time_str,
      "end_time" => end_time_str,
      "attendee_emails" => attendee_emails
    } = arguments

    description = arguments["description"] || ""

    with {:ok, start_time} <- parse_datetime(start_time_str),
         {:ok, end_time} <- parse_datetime(end_time_str) do
      event_attrs = %{
        title: title,
        description: description,
        start_time: start_time,
        end_time: end_time,
        attendees: attendee_emails
      }

      case Agentleguide.Services.Google.CalendarService.create_event(user, event_attrs) do
        {:ok, event} ->
          {:ok,
           %{
             "status" => "created",
             "event_id" => event["id"],
             "message" => "Meeting '#{title}' scheduled successfully"
           }}

        {:error, reason} ->
          {:error, "Failed to schedule meeting: #{inspect(reason)}"}
      end
    else
      {:error, reason} ->
        {:error, "Invalid datetime format: #{reason}"}
    end
  end

  defp create_hubspot_contact(user, arguments) do
    contact_attrs = %{
      email: arguments["email"],
      first_name: arguments["first_name"],
      last_name: arguments["last_name"],
      company: arguments["company"],
      phone: arguments["phone"]
    }

          case Agentleguide.Services.Hubspot.HubspotService.create_contact(user, contact_attrs) do
      {:ok, contact} ->
        {:ok,
         %{
           "status" => "created",
           "contact_id" => contact.id,
           "message" => "Contact created successfully in HubSpot"
         }}

      {:error, reason} ->
        {:error, "Failed to create contact: #{inspect(reason)}"}
    end
  end

  defp get_upcoming_events(user, arguments) do
    days = arguments["days"] || 7

          case Agentleguide.Services.Google.CalendarService.get_upcoming_events(user, days) do
      {:ok, events} ->
        formatted_events =
          Enum.map(events, fn event ->
            %{
              "id" => event["id"],
              "title" => event["summary"],
              "start_time" =>
                get_in(event, ["start", "dateTime"]) || get_in(event, ["start", "date"]),
              "end_time" => get_in(event, ["end", "dateTime"]) || get_in(event, ["end", "date"]),
              "description" => event["description"]
            }
          end)

        {:ok, %{"events" => formatted_events, "count" => length(formatted_events)}}

      {:error, reason} ->
        {:error, "Failed to get upcoming events: #{inspect(reason)}"}
    end
  end

  # Helper functions

    defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        naive_datetime = NaiveDateTime.new!(date, ~T[09:00:00])
        {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_date(_), do: {:error, "Invalid date"}

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_datetime(_), do: {:error, "Invalid datetime"}
end

defmodule Agentleguide.Services.Ai.AiService do
  @moduledoc """
  Service for interacting with AI APIs.
  Supports dependency injection for different AI clients.
  """

  require Logger

  alias Agentleguide.Services.Ai.Clients.{OpenaiClient, OllamaClient, MockClient}

  @doc """
  Generate embeddings for the given text using the configured AI backend.

  Options:
  - `:client` - Override the default client (e.g., MockClient for testing)
  """
  def generate_embeddings(text, opts \\ []) do
    # Check if embeddings are enabled
    if Application.get_env(:agentleguide, :embeddings_enabled, true) do
      client = get_client(opts)
      client.generate_embeddings(text)
    else
      Logger.debug("Embeddings disabled in configuration")
      {:error, "Embeddings disabled"}
    end
  end

  @doc """
  Generate a chat completion with context from RAG and tool calling support.

  Options:
  - `:client` - Override the default client (e.g., MockClient for testing)
  """
  def chat_completion(messages, context \\ [], user \\ nil, opts \\ []) do
    client = get_client(opts)

    # Build system message with context
    system_message = build_system_message(context, user)
    all_messages = [system_message | messages]

    # Prepare options for the client
    client_opts = []
    client_opts = if user, do: Keyword.put(client_opts, :user, user), else: client_opts

    client_opts =
      if user, do: Keyword.put(client_opts, :tools, get_available_tools()), else: client_opts

    client.chat_completion(all_messages, client_opts)
  end

  # Private functions

  defp get_client(opts) do
    case Keyword.get(opts, :client) || get_default_client() do
      :openai -> OpenaiClient
      :ollama -> OllamaClient
      :mock -> MockClient
      module when is_atom(module) -> module
    end
  end

  defp get_default_client do
    Application.get_env(:agentleguide, :ai_backend, :openai)
  end

  defp build_system_message(context, user) do
    base_message = """
    You are a helpful AI assistant with access to the user's personal data including emails, contacts, and calendar.
    When answering questions, use the following context from their data if relevant:

    #{format_context(context)}

    IMPORTANT: When users ask about emails (like "show me my recent emails", "what's my latest email", "any new emails"),
    you MUST call the search_emails tool immediately - do not just suggest it. Same for contacts and calendar.

    Always be proactive in using tools to answer user questions directly rather than just suggesting what they could do.
    """

    enhanced_message =
      if user do
        base_message <> build_tool_instructions()
      else
        base_message
      end

    %{
      "role" => "system",
      "content" => enhanced_message
    }
  end

  defp format_context(nil), do: "No additional context available."
  defp format_context([]), do: "No additional context available."

  defp format_context(context) when is_list(context) do
    context
    |> Enum.with_index(1)
    |> Enum.map(fn {doc, index} ->
      source = Map.get(doc, :source) || Map.get(doc, "source") || "Unknown source"
      content = Map.get(doc, :content) || Map.get(doc, "content") || ""

      "#{index}. Source: #{source}\n   Content: #{String.slice(content, 0, 200)}..."
    end)
    |> Enum.join("\n\n")
  end

  defp build_tool_instructions do
    """

    You have access to the following tools and MUST use them when relevant:

    1. search_emails - Search through Gmail emails. Parameters:
       - query: Use for searching email content, subjects, or keywords (optional)
       - sender: Use for searching emails FROM a specific person (optional)
       - limit: Maximum emails to return (default: 10, optional)

    2. search_contacts(query) - Search for EXISTING contacts by name, email, or company.
       - query: Search term (optional - if not provided, returns ALL contacts)

    3. send_email(to_email, subject, body) - Send an email
    4. get_upcoming_events(days) - Get upcoming calendar events
    5. get_available_time_slots(start_date, end_date, duration_minutes) - Get available time slots
    6. schedule_meeting(title, start_time, end_time, attendee_emails, description) - Schedule a meeting
    7. create_hubspot_contact(email, first_name, last_name, company, phone) - Create a NEW contact

    CRITICAL TOOL USAGE RULES - YOU MUST FOLLOW THESE:
    - "show me my recent emails" → IMMEDIATELY call search_emails() with no parameters
    - "what's my latest email" → IMMEDIATELY call search_emails() with limit=1
    - "any new emails" → IMMEDIATELY call search_emails() with no parameters
    - "emails from [person]" → IMMEDIATELY call search_emails(sender="person name")
    - "emails about [topic]" → IMMEDIATELY call search_emails(query="topic")
    - "find contact [name]" → IMMEDIATELY call search_contacts(query="name")
    - "how many contacts do I have?" → IMMEDIATELY call search_contacts() with no parameters

    DO NOT just suggest using tools - ACTUALLY USE THEM to answer the user's question!
    """
  end

  defp get_available_tools do
    # Return tools configuration if needed by the client
    # This could be expanded to return OpenAI-style tool definitions
    Agentleguide.Services.Ai.AiTools.get_available_tools()
  end
end

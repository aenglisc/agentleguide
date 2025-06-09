defmodule Agentleguide.Services.Ai.ChatService do
  @moduledoc """
  Service for handling RAG-powered chat conversations.
  Orchestrates query processing, context retrieval, and AI response generation.
  """

  alias Agentleguide.Rag
  alias Agentleguide.Services.Ai.AiService
  alias Agentleguide.Rag.{HubspotContact}
  require Logger

  @doc """
  Process a user query and generate an AI response with context.
  Creates a new session if one doesn't exist.
  """
  def process_query(user, session_id, query) do
    if is_nil(user) do
      {:error, :invalid_user}
    else
      with {:ok, _session} <- ensure_session_exists(user, session_id, query),
         {:ok, _} <- save_user_message(user, session_id, query),
         {:ok, context} <- get_relevant_context(user, query),
         {:ok, response} <- generate_response(user, session_id, query, context),
         {:ok, _} <- save_assistant_message(user, session_id, response),
         {:ok, _} <- update_session_activity(user, session_id) do
      {:ok, response}
    else
      {:error, reason} ->
        Logger.error("Failed to process query: #{inspect(reason)}")
        {:error, reason}
    end
    end
  end

  @doc """
  Creates a new chat session for a user.
  """
  def create_new_session(user, first_message \\ nil) do
    session_id = generate_session_id()

    case Rag.create_chat_session(user, %{
           session_id: session_id,
           first_message: first_message,
           last_message_at: DateTime.utc_now()
         }) do
      {:ok, session} -> {:ok, session}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets a chat session with its messages.
  """
  def get_session_with_messages(user, session_id) do
    case Rag.get_chat_session(user, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        messages = Rag.get_chat_messages(user, session_id)
        {:ok, %{session: session, messages: messages}}
    end
  end

  @doc """
  Lists all active chat sessions for a user.
  """
  def list_user_sessions(user, limit \\ 20) do
    Rag.list_chat_sessions(user, limit)
  end

  @doc """
  Handle potential ambiguous person queries by checking for multiple matches.
  """
  def handle_person_query(user, query) do
    # Extract potential names from the query
    potential_names = extract_names_from_query(query)

    # Search for contacts matching any of the potential names
    contacts =
      potential_names
      |> Enum.flat_map(&Rag.search_contacts(user, &1))
      |> Enum.uniq_by(& &1.id)

    case contacts do
      [] ->
        {:no_matches, []}

      [_single_contact] ->
        {:single_match, contacts}

      multiple_contacts ->
        {:multiple_matches, multiple_contacts}
    end
  end

  defp save_user_message(user, session_id, content) do
    Rag.create_chat_message(%{
      user_id: user.id,
      session_id: session_id,
      role: "user",
      content: content
    })
  end

  defp save_assistant_message(user, session_id, content) do
    Rag.create_chat_message(%{
      user_id: user.id,
      session_id: session_id,
      role: "assistant",
      content: content
    })
  end

  defp get_relevant_context(user, query) do
    with {:ok, query_embedding} <- AiService.generate_embeddings(query) do
      similar_docs = Rag.search_similar_documents(user, query_embedding, 5)
      {:ok, similar_docs}
    else
      {:error, "Embeddings disabled"} ->
        # Silently proceed without context when embeddings are disabled (e.g., in tests)
        {:ok, []}

      {:error, reason} ->
        Logger.warning("Failed to get embeddings, proceeding without context: #{inspect(reason)}")
        {:ok, []}
    end
  end

  defp generate_response(user, session_id, query, context) do
    # Get recent chat history for context
    recent_messages =
      Rag.get_chat_messages(user, session_id)
      # Last 10 messages
      |> Enum.take(-10)
      |> Enum.map(&format_message_for_ai/1)

    # Check for person ambiguity first
    case handle_person_query(user, query) do
      {:multiple_matches, contacts} ->
        generate_disambiguation_response(contacts)

      _ ->
        # Proceed with normal RAG response with tool calling support
        AiService.chat_completion(
          recent_messages ++ [%{"role" => "user", "content" => query}],
          context,
          user
        )
    end
  end

  defp generate_disambiguation_response(contacts) do
    contact_list =
      contacts
      |> Enum.with_index(1)
      |> Enum.map(fn {contact, idx} ->
        name = HubspotContact.display_name(contact)
        company = if contact.company, do: " (#{contact.company})", else: ""
        "#{idx}. #{name}#{company}"
      end)
      |> Enum.join("\n")

    response = """
    I found multiple people with that name. Could you clarify which one you're asking about?

    #{contact_list}

    Please let me know which person you'd like to know more about.
    """

    {:ok, response}
  end

  defp format_message_for_ai(message) do
    %{
      "role" => message.role,
      "content" => message.content
    }
  end

  defp extract_names_from_query(query) do
    # Simple name extraction - look for capitalized words that might be names
    # This is a basic implementation - could be enhanced with NLP
    query
    |> String.split()
    |> Enum.filter(fn word ->
      # Look for capitalized words that are likely names
      String.match?(word, ~r/^[A-Z][a-z]+$/) and
        String.length(word) > 2 and
        String.downcase(word) not in [
          "I",
          "The",
          "And",
          "But",
          "Or",
          "For",
          "At",
          "In",
          "On",
          "To",
          "From"
        ]
    end)
    |> Enum.uniq()
  end

  defp ensure_session_exists(user, session_id, query) do
    case Rag.get_chat_session(user, session_id) do
      nil ->
        # Create new session with the first message as title
        Rag.create_chat_session(user, %{
          session_id: session_id,
          first_message: query,
          last_message_at: DateTime.utc_now()
        })

      session ->
        {:ok, session}
    end
  end

  defp update_session_activity(user, session_id) do
    Rag.update_chat_session_activity(user, session_id)
  end

  @doc """
  Generate a new session ID for chat conversations.
  """
  def generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end
end

defmodule Agentleguide.Rag do
  @moduledoc """
  The RAG (Retrieval-Augmented Generation) context.
  Handles Gmail emails, HubSpot contacts/notes, embeddings, and chat functionality.
  """

  import Ecto.Query, warn: false
  alias Agentleguide.Repo

  alias Agentleguide.Rag.{
    GmailEmail,
    HubspotContact,
    HubspotNote,
    DocumentEmbedding,
    ChatMessage,
    ChatSession
  }

  ## Gmail Email functions

  @doc """
  Returns the list of gmail emails for a user.
  """
  def list_gmail_emails(%{id: user_id}) do
    GmailEmail
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.date)
    |> Repo.all()
  end

  @doc """
  Gets a single gmail email.
  """
  def get_gmail_email!(id), do: Repo.get!(GmailEmail, id)

  @doc """
  Creates or updates a gmail email.
  """
  def upsert_gmail_email(user, attrs \\ %{}) do
    case Repo.get_by(GmailEmail,
           user_id: user.id,
           gmail_id: attrs["gmail_id"] || attrs[:gmail_id]
         ) do
      nil ->
        %GmailEmail{}
        |> GmailEmail.changeset(Map.put(attrs, :user_id, user.id))
        |> Repo.insert()

      existing ->
        existing
        |> GmailEmail.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Get the latest gmail email for a user (for incremental sync).
  """
  def get_latest_gmail_email(%{id: user_id}) do
    GmailEmail
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.date, desc: e.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Get existing Gmail IDs from a list (to avoid re-fetching).
  """
  def get_existing_gmail_ids(%{id: user_id}, gmail_ids) when is_list(gmail_ids) do
    GmailEmail
    |> where([e], e.user_id == ^user_id and e.gmail_id in ^gmail_ids)
    |> select([e], e.gmail_id)
    |> Repo.all()
  end

  def get_existing_gmail_ids(_user, []), do: []

  @doc """
  Search emails by content, subject, or body text.
  If no query is provided, returns recent emails.
  """
  def search_emails(user, query, limit \\ 10)

  def search_emails(%{id: user_id}, query, limit)
      when is_binary(query) and byte_size(query) > 0 do
    query_pattern = "%#{String.downcase(query)}%"

    results =
      GmailEmail
      |> where([e], e.user_id == ^user_id)
      |> where(
        [e],
        ilike(e.subject, ^query_pattern) or
          ilike(e.body_text, ^query_pattern) or
          ilike(e.from_name, ^query_pattern) or
          ilike(e.from_email, ^query_pattern)
      )
      # Order by relevance: subject matches first, then recent emails
      |> order_by([e],
        desc: fragment("CASE WHEN LOWER(?) LIKE ? THEN 1 ELSE 0 END", e.subject, ^query_pattern),
        desc: e.date
      )
      # Get more results to filter
      |> limit(^(limit * 2))
      |> Repo.all()

    # Filter and rank results by relevance
    results
    |> filter_relevant_emails(query)
    |> Enum.take(limit)
  end

  def search_emails(%{id: user_id}, _query, limit) do
    # If no query or empty query, return recent emails
    get_recent_emails(%{id: user_id}, limit)
  end

  @doc """
  Search emails by sender and optionally by content.
  """
  def search_emails_by_sender(%{id: user_id}, sender, query \\ "", limit \\ 10) do
    sender_pattern = "%#{String.downcase(sender)}%"

    base_query =
      GmailEmail
      |> where([e], e.user_id == ^user_id)
      |> where(
        [e],
        ilike(e.from_name, ^sender_pattern) or
          ilike(e.from_email, ^sender_pattern)
      )

    final_query =
      if query != "" do
        query_pattern = "%#{String.downcase(query)}%"

        base_query
        |> where(
          [e],
          ilike(e.subject, ^query_pattern) or
            ilike(e.body_text, ^query_pattern)
        )
      else
        base_query
      end

    final_query
    |> order_by([e], desc: e.date)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get recent emails for a user.
  """
  def get_recent_emails(%{id: user_id}, limit \\ 10) do
    GmailEmail
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.date)
    |> limit(^limit)
    |> Repo.all()
  end

  ## HubSpot Contact functions

  @doc """
  Returns the list of hubspot contacts for a user.
  """
  def list_hubspot_contacts(%{id: user_id}) do
    HubspotContact
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> Repo.all()
  end

  @doc """
  Returns the count of hubspot contacts for a user.
  """
  def count_hubspot_contacts(%{id: user_id}) do
    HubspotContact
    |> where([c], c.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Gets a single hubspot contact.
  """
  def get_hubspot_contact!(id), do: Repo.get!(HubspotContact, id)

  @doc """
  Creates or updates a hubspot contact.
  """
  def upsert_hubspot_contact(user, attrs \\ %{}) do
    case Repo.get_by(HubspotContact,
           user_id: user.id,
           hubspot_id: attrs["hubspot_id"] || attrs[:hubspot_id]
         ) do
      nil ->
        %HubspotContact{}
        |> HubspotContact.changeset(Map.put(attrs, :user_id, user.id))
        |> Repo.insert()

      existing ->
        existing
        |> HubspotContact.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Search contacts by name (first name, last name, or company).
  """
  def search_contacts(user, query) when byte_size(query) > 0 do
    query_pattern = "%#{String.downcase(query)}%"

    HubspotContact
    |> where([c], c.user_id == ^user.id)
    |> where(
      [c],
      ilike(c.first_name, ^query_pattern) or
        ilike(c.last_name, ^query_pattern) or
        ilike(c.company, ^query_pattern)
    )
    |> order_by([c], asc: c.last_name, asc: c.first_name)
    |> Repo.all()
  end

  def search_contacts(_user, _query), do: []

  @doc """
  Get existing HubSpot contact sync times for comparison during incremental sync.
  Returns a map of hubspot_id => last_synced_at.
  """
  def get_hubspot_contact_sync_times(%{id: user_id}, hubspot_ids) when is_list(hubspot_ids) do
    HubspotContact
    |> where([c], c.user_id == ^user_id and c.hubspot_id in ^hubspot_ids)
    |> select([c], {c.hubspot_id, c.last_synced_at})
    |> Repo.all()
    |> Enum.into(%{})
  end

  def get_hubspot_contact_sync_times(_user, []), do: %{}

  ## HubSpot Notes functions

  @doc """
  Creates or updates a hubspot note.
  """
  def upsert_hubspot_note(user, contact, attrs \\ %{}) do
    case Repo.get_by(HubspotNote,
           user_id: user.id,
           hubspot_id: attrs["hubspot_id"] || attrs[:hubspot_id]
         ) do
      nil ->
        %HubspotNote{}
        |> HubspotNote.changeset(Map.merge(attrs, %{user_id: user.id, contact_id: contact.id}))
        |> Repo.insert()

      existing ->
        existing
        |> HubspotNote.changeset(attrs)
        |> Repo.update()
    end
  end

  ## Document Embedding functions

  @doc """
  Creates a document embedding.
  """
  def create_document_embedding(attrs \\ %{}) do
    %DocumentEmbedding{}
    |> DocumentEmbedding.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Search for similar documents using vector similarity.
  """
  def search_similar_documents(user, query_embedding, limit \\ 10) do
    DocumentEmbedding
    |> where([de], de.user_id == ^user.id)
    |> order_by([de], fragment("embedding <=> ?", ^query_embedding))
    |> limit(^limit)
    |> Repo.all()
  end

  ## Chat Message functions

  @doc """
  Creates a chat message.
  """
  def create_chat_message(attrs \\ %{}) do
    %ChatMessage{}
    |> ChatMessage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets chat messages for a session.
  """
  def get_chat_messages(user, session_id) do
    ChatMessage
    |> where([cm], cm.user_id == ^user.id and cm.session_id == ^session_id)
    |> order_by([cm], asc: cm.inserted_at)
    |> Repo.all()
  end

  ## Chat Session functions

  @doc """
  Creates a new chat session for a user.
  """
  def create_chat_session(user, attrs \\ %{}) do
    session_id = attrs[:session_id] || generate_session_id()

    attrs =
      attrs
      |> Map.put(:user_id, user.id)
      |> Map.put(:session_id, session_id)
      |> Map.put_new(:title, generate_session_title(attrs[:first_message]))

    %ChatSession{}
    |> ChatSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a chat session by session_id for a user.
  """
  def get_chat_session(user, session_id) do
    ChatSession
    |> where([cs], cs.user_id == ^user.id and cs.session_id == ^session_id)
    |> Repo.one()
  end

  @doc """
  Gets a chat session by id for a user.
  """
  def get_chat_session!(user, id) do
    ChatSession
    |> where([cs], cs.user_id == ^user.id and cs.id == ^id)
    |> Repo.one!()
  end

  @doc """
  Lists all chat sessions for a user, ordered by most recent activity.
  """
  def list_chat_sessions(user, limit \\ 20) do
    ChatSession
    |> where([cs], cs.user_id == ^user.id and cs.is_active == true)
    |> order_by([cs], desc: cs.last_message_at, desc: cs.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Updates a chat session's metadata when a new message is added.
  """
  def update_chat_session_activity(user, session_id) do
    case get_chat_session(user, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        session
        |> ChatSession.changeset(%{
          last_message_at: DateTime.utc_now(),
          message_count: session.message_count + 1
        })
        |> Repo.update()
    end
  end

  @doc """
  Updates a chat session's title.
  """
  def update_chat_session_title(user, session_id, title) do
    case get_chat_session(user, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        session
        |> ChatSession.changeset(%{title: title})
        |> Repo.update()
    end
  end

  @doc """
  Archives a chat session (sets is_active to false).
  """
  def archive_chat_session(user, session_id) do
    case get_chat_session(user, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        session
        |> ChatSession.changeset(%{is_active: false})
        |> Repo.update()
    end
  end

  @doc """
  Deletes a chat session and all its messages.
  """
  def delete_chat_session(user, session_id) do
    case get_chat_session(user, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        Repo.transaction(fn ->
          # Delete all messages for this session
          ChatMessage
          |> where([cm], cm.user_id == ^user.id and cm.session_id == ^session_id)
          |> Repo.delete_all()

          # Delete the session itself
          Repo.delete!(session)
        end)
    end
  end

  @doc """
  Gets recent chat sessions for a user (deprecated - use list_chat_sessions/2).
  """
  def get_recent_chat_sessions(user, limit \\ 10) do
    ChatMessage
    |> where([cm], cm.user_id == ^user.id)
    |> group_by([cm], cm.session_id)
    |> select([cm], %{
      session_id: cm.session_id,
      last_message_at: max(cm.inserted_at),
      message_count: count(cm.id)
    })
    |> order_by([cm], desc: max(cm.inserted_at))
    |> limit(^limit)
    |> Repo.all()
  end

  # Private helper functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode64() |> binary_part(0, 16)
  end

  defp generate_session_title(nil), do: "New Chat"

  defp generate_session_title(first_message) when is_binary(first_message) do
    # Take first 50 characters of the message as title
    first_message
    |> String.trim()
    |> String.slice(0, 50)
    |> case do
      "" ->
        "New Chat"

      title ->
        if String.length(title) == 50 do
          title <> "..."
        else
          title
        end
    end
  end

  defp generate_session_title(_), do: "New Chat"

  # Filter emails by relevance to query
  defp filter_relevant_emails(emails, query) do
    query_lower = String.downcase(query)

    emails
    |> Enum.map(fn email ->
      relevance_score = calculate_email_relevance(email, query_lower)
      {email, relevance_score}
    end)
    # Only keep relevant emails
    |> Enum.filter(fn {_email, score} -> score > 0 end)
    # Sort by relevance
    |> Enum.sort_by(fn {_email, score} -> score end, :desc)
    |> Enum.map(fn {email, _score} -> email end)
  end

  # Calculate relevance score for an email
  defp calculate_email_relevance(email, query_lower) do
    subject = String.downcase(email.subject || "")
    body = String.downcase(email.body_text || "")
    from_name = String.downcase(email.from_name || "")

    base_score = 0

    # Check if sender is clearly a digest/newsletter service
    is_digest_sender =
      String.contains?(from_name, "digest") or
        String.contains?(from_name, "newsletter") or
        String.contains?(from_name, "shopify") or
        String.contains?(from_name, "quora") or
        String.contains?(from_name, "notifications")

    # High score for subject matches
    subject_score = if String.contains?(subject, query_lower), do: 10, else: 0

    # Medium score for body matches (but not in URLs or technical content)
    is_spam_or_digest =
      email_body_looks_like_spam_or_digest(body, query_lower) or is_digest_sender

    body_score =
      if String.contains?(body, query_lower) and not is_spam_or_digest do
        5
      else
        0
      end

    # Lower score for sender name matches (but not for digest senders)
    sender_score =
      if String.contains?(from_name, query_lower) and not is_digest_sender, do: 2, else: 0

    base_score + subject_score + body_score + sender_score
  end

  # Check if email body looks like spam, digest, or automated content
  defp email_body_looks_like_spam_or_digest(body, query) do
    # Check for digest/newsletter patterns in body
    digest_patterns = [
      "top stories",
      "digest",
      "newsletter",
      "unsubscribe",
      "email preferences",
      "www.",
      "http",
      "click here",
      "view this email",
      "forwarded message"
    ]

    # Check for URL/encoded patterns where query appears
    query_context = extract_context_around_query(body, query)
    # Long random strings
    appears_in_url =
      String.contains?(query_context, "%") or
        String.contains?(query_context, "http") or
        String.match?(query_context, ~r/[a-z0-9]{10,}/)

    # Check if it's from a digest/newsletter sender (more reliable than body content)
    is_digest_sender =
      String.contains?(String.downcase(body), "digest") or
        String.contains?(String.downcase(body), "newsletter") or
        String.contains?(String.downcase(body), "unsubscribe")

    # Check for topic list patterns (multiple topics separated by punctuation)
    appears_in_topic_list = String.match?(query_context, ~r/[,;•\n].*#{query}.*[,;•\n]/)

    # If the query appears very briefly (might be just a topic in a list)
    brief_mention = String.length(query_context) < 50

    # Check for any spam indicators
    has_spam_patterns =
      Enum.any?(digest_patterns, fn pattern ->
        String.contains?(body, pattern)
      end)

    # Return true if it's clearly spam/digest content
    appears_in_url or
      is_digest_sender or
      (appears_in_topic_list and brief_mention) or
      (has_spam_patterns and brief_mention)
  end

  # Extract a small context around where the query appears
  defp extract_context_around_query(text, query) do
    case String.split(text, query, parts: 2) do
      [before, after_text] ->
        # Take 25 chars before and after the query
        before_context = String.slice(before, -25..-1) || ""
        after_context = String.slice(after_text, 0..25) || ""
        before_context <> query <> after_context

      _ ->
        ""
    end
  end
end

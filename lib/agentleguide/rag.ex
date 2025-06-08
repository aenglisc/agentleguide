defmodule Agentleguide.Rag do
  @moduledoc """
  The RAG (Retrieval-Augmented Generation) context.
  Handles Gmail emails, HubSpot contacts/notes, embeddings, and chat functionality.
  """

  import Ecto.Query, warn: false
  alias Agentleguide.Repo
  alias Agentleguide.Rag.{GmailEmail, HubspotContact, HubspotNote, DocumentEmbedding, ChatMessage}

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

    GmailEmail
    |> where([e], e.user_id == ^user_id)
    |> where(
      [e],
      ilike(e.subject, ^query_pattern) or
        ilike(e.body_text, ^query_pattern) or
        ilike(e.from_name, ^query_pattern) or
        ilike(e.from_email, ^query_pattern)
    )
    |> order_by([e], desc: e.date)
    |> limit(^limit)
    |> Repo.all()
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

  @doc """
  Gets recent chat sessions for a user.
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
end

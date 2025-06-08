defmodule Agentleguide.Jobs.EmbeddingJob do
  @moduledoc """
  Background job for generating embeddings for emails and other documents.
  """

  use Oban.Worker, queue: :ai, max_attempts: 3

  require Logger
  alias Agentleguide.{Accounts, Rag, AiService}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "email_id" => email_id}}) do
    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, email} <- get_email(email_id) do
      generate_email_embeddings(user, email)
    else
      {:error, :not_found} ->
        Logger.warning("User #{user_id} or email #{email_id} not found for embedding generation")
        {:discard, "User or email not found"}

      {:error, reason} ->
        Logger.error("Failed to generate embeddings for email #{email_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "contact_id" => contact_id}}) do
    with {:ok, user} <- Accounts.get_user(user_id),
         {:ok, contact} <- get_contact(contact_id) do
      generate_contact_embeddings(user, contact)
    else
      {:error, :not_found} ->
        Logger.warning(
          "User #{user_id} or contact #{contact_id} not found for embedding generation"
        )

        {:discard, "User or contact not found"}

      {:error, reason} ->
        Logger.error(
          "Failed to generate embeddings for contact #{contact_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  # Private functions

  defp get_email(email_id) do
    try do
      email = Rag.get_gmail_email!(email_id)
      {:ok, email}
    rescue
      Ecto.NoResultsError ->
        {:error, :not_found}
    end
  end

  defp get_contact(contact_id) do
    try do
      contact = Rag.get_hubspot_contact!(contact_id)
      {:ok, contact}
    rescue
      Ecto.NoResultsError ->
        {:error, :not_found}
    end
  end

  defp generate_email_embeddings(user, email) do
    # Create content for embedding (subject + body_text)
    body_content = email.body_text || ""
    content = "#{email.subject}\n\n#{body_content}"

    # Skip embedding if content is too short or empty
    if String.length(String.trim(content)) < 10 do
      Logger.debug("Skipping embedding generation for email #{email.id}: content too short")
      :ok
    else
      case AiService.generate_embeddings(content) do
        {:ok, embeddings} ->
          embedding_attrs = %{
            document_type: "gmail_email",
            document_id: email.id,
            content: content,
            embedding: embeddings,
            metadata: %{
              "subject" => email.subject,
              "from_email" => email.from_email,
              "from_name" => email.from_name,
              "to_emails" => email.to_emails,
              "date" => email.date
            },
            chunk_index: 0,
            user_id: user.id
          }

          case Rag.create_document_embedding(embedding_attrs) do
            {:ok, _embedding} ->
              Logger.debug("Successfully created embedding for email #{email.id}")
              :ok

            {:error, reason} ->
              Logger.warning("Failed to save embedding for email #{email.id}: #{inspect(reason)}")
              {:error, reason}
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to generate embeddings for email #{email.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp generate_contact_embeddings(user, contact) do
    # Create content for embedding from contact information
    content = build_contact_content(contact)

    if String.length(String.trim(content)) < 5 do
      Logger.debug("Skipping embedding generation for contact #{contact.id}: content too short")
      :ok
    else
      case AiService.generate_embeddings(content) do
        {:ok, embeddings} ->
          embedding_attrs = %{
            document_type: "hubspot_contact",
            document_id: contact.id,
            content: content,
            embedding: embeddings,
            metadata: %{
              "first_name" => contact.first_name,
              "last_name" => contact.last_name,
              "email" => contact.email,
              "company" => contact.company,
              "phone" => contact.phone
            },
            chunk_index: 0,
            user_id: user.id
          }

          case Rag.create_document_embedding(embedding_attrs) do
            {:ok, _embedding} ->
              Logger.debug("Successfully created embedding for contact #{contact.id}")
              :ok

            {:error, reason} ->
              Logger.warning(
                "Failed to save embedding for contact #{contact.id}: #{inspect(reason)}"
              )

              {:error, reason}
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to generate embeddings for contact #{contact.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp build_contact_content(contact) do
    parts =
      [
        contact.first_name,
        contact.last_name,
        contact.email,
        contact.company,
        contact.phone,
        contact.job_title,
        contact.website
      ]
      |> Enum.filter(& &1)
      |> Enum.reject(&(String.trim(&1) == ""))

    Enum.join(parts, " ")
  end
end

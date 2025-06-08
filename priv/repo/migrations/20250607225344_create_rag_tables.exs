defmodule Agentleguide.Repo.Migrations.CreateRagTables do
  use Ecto.Migration

  def change do
    # Gmail emails table
    create table(:gmail_emails, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      # Gmail message ID
      add :gmail_id, :string, null: false
      # Gmail thread ID
      add :thread_id, :string
      add :subject, :text
      add :from_email, :string
      add :from_name, :string
      add :to_emails, {:array, :string}
      add :cc_emails, {:array, :string}
      add :bcc_emails, {:array, :string}
      add :body_text, :text
      add :body_html, :text
      add :date, :utc_datetime
      add :labels, {:array, :string}
      add :has_attachments, :boolean, default: false
      add :is_read, :boolean, default: false
      add :is_important, :boolean, default: false
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # HubSpot contacts table
    create table(:hubspot_contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      # HubSpot contact ID
      add :hubspot_id, :string, null: false
      add :email, :string
      add :first_name, :string
      add :last_name, :string
      add :company, :string
      add :job_title, :string
      add :phone, :string
      add :website, :string
      add :city, :string
      add :state, :string
      add :country, :string
      add :lifecycle_stage, :string
      add :lead_status, :string
      add :owner_id, :string
      add :last_modified_date, :utc_datetime
      add :created_date, :utc_datetime
      # Store all HubSpot properties as JSON
      add :properties, :jsonb
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # HubSpot contact notes/activities table
    create table(:hubspot_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      add :contact_id, references(:hubspot_contacts, on_delete: :delete_all, type: :binary_id),
        null: false

      # HubSpot engagement/note ID
      add :hubspot_id, :string, null: false
      # NOTE, TASK, CALL, EMAIL, MEETING, etc.
      add :note_type, :string
      add :subject, :string
      add :body, :text
      add :created_date, :utc_datetime
      add :last_modified_date, :utc_datetime
      add :owner_id, :string
      # Store additional properties
      add :properties, :jsonb
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Document embeddings table (for RAG)
    create table(:document_embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      # "gmail_email", "hubspot_contact", "hubspot_note"
      add :document_type, :string, null: false
      # References the specific document
      add :document_id, :binary_id, null: false
      # The text content that was embedded
      add :content, :text, null: false
      # OpenAI embedding dimension
      add :embedding, :vector, size: 1536
      # Additional metadata (e.g., from/to, subject, etc.)
      add :metadata, :jsonb
      # For large documents split into chunks
      add :chunk_index, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    # Chat messages table
    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      # Group messages into conversations
      add :session_id, :string, null: false
      # "user" or "assistant"
      add :role, :string, null: false
      add :content, :text, null: false
      # Store additional context, sources, etc.
      add :metadata, :jsonb

      timestamps(type: :utc_datetime)
    end

    # Indexes for performance
    create index(:gmail_emails, [:user_id])
    create index(:gmail_emails, [:gmail_id])
    create index(:gmail_emails, [:thread_id])
    create index(:gmail_emails, [:from_email])
    create index(:gmail_emails, [:date])

    create index(:hubspot_contacts, [:user_id])
    create index(:hubspot_contacts, [:hubspot_id])
    create index(:hubspot_contacts, [:email])
    create index(:hubspot_contacts, [:first_name, :last_name])
    create index(:hubspot_contacts, [:company])

    create index(:hubspot_notes, [:user_id])
    create index(:hubspot_notes, [:contact_id])
    create index(:hubspot_notes, [:hubspot_id])
    create index(:hubspot_notes, [:created_date])

    create index(:document_embeddings, [:user_id])
    create index(:document_embeddings, [:document_type])
    create index(:document_embeddings, [:document_id])
    # Create vector similarity search index
    execute "CREATE INDEX IF NOT EXISTS document_embeddings_embedding_idx ON document_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"

    create index(:chat_messages, [:user_id])
    create index(:chat_messages, [:session_id])
    create index(:chat_messages, [:inserted_at])

    # Unique constraints
    create unique_index(:gmail_emails, [:user_id, :gmail_id])
    create unique_index(:hubspot_contacts, [:user_id, :hubspot_id])
    create unique_index(:hubspot_notes, [:user_id, :hubspot_id])
  end
end

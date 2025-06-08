defmodule Agentleguide.Rag.DocumentEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "document_embeddings" do
    field :document_type, :string
    field :document_id, :binary_id
    field :content, :string
    field :embedding, Pgvector.Ecto.Vector
    field :metadata, :map
    field :chunk_index, :integer, default: 0

    belongs_to :user, Agentleguide.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document_embedding, attrs) do
    document_embedding
    |> cast(attrs, [
      :user_id,
      :document_type,
      :document_id,
      :content,
      :embedding,
      :metadata,
      :chunk_index
    ])
    |> validate_required([:user_id, :document_type, :document_id, :content, :embedding])
    |> validate_inclusion(:document_type, ["gmail_email", "hubspot_contact", "hubspot_note"])
    |> foreign_key_constraint(:user_id)
  end
end

defmodule Agentleguide.Rag.ChatSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_sessions" do
    field :title, :string
    field :description, :string
    field :session_id, :string
    field :is_active, :boolean, default: true
    field :last_message_at, :utc_datetime
    field :message_count, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :user, Agentleguide.Accounts.User
    has_many :messages, Agentleguide.Rag.ChatMessage, foreign_key: :session_id, references: :session_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_session, attrs) do
    chat_session
    |> cast(attrs, [:user_id, :title, :description, :session_id, :is_active, :last_message_at, :message_count, :metadata])
    |> validate_required([:user_id, :session_id])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 1000)
    |> unique_constraint([:user_id, :session_id])
    |> foreign_key_constraint(:user_id)
  end
end

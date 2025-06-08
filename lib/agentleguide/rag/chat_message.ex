defmodule Agentleguide.Rag.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_messages" do
    field :session_id, :string
    field :role, :string
    field :content, :string
    field :metadata, :map

    belongs_to :user, Agentleguide.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(chat_message, attrs) do
    chat_message
    |> cast(attrs, [:user_id, :session_id, :role, :content, :metadata])
    |> validate_required([:user_id, :session_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant"])
    |> foreign_key_constraint(:user_id)
  end
end

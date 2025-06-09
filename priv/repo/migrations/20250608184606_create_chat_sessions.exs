defmodule Agentleguide.Repo.Migrations.CreateChatSessions do
  use Ecto.Migration

  def change do
    create table(:chat_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :description, :text
      add :session_id, :string, null: false
      add :is_active, :boolean, default: true, null: false
      add :last_message_at, :utc_datetime
      add :message_count, :integer, default: 0, null: false
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_sessions, [:user_id])
    create index(:chat_sessions, [:user_id, :last_message_at])
    create index(:chat_sessions, [:user_id, :is_active])
    create unique_index(:chat_sessions, [:user_id, :session_id])
  end
end

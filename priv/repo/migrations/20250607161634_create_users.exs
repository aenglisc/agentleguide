defmodule Agentleguide.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :avatar_url, :string

      # Google OAuth fields
      add :google_uid, :string
      add :google_access_token, :text
      add :google_refresh_token, :text
      add :google_token_expires_at, :utc_datetime

      # Integration status
      add :gmail_connected_at, :utc_datetime
      add :calendar_connected_at, :utc_datetime
      add :hubspot_connected_at, :utc_datetime

      # HubSpot OAuth fields
      add :hubspot_access_token, :text
      add :hubspot_refresh_token, :text
      add :hubspot_token_expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_uid])
  end
end

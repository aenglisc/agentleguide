defmodule Agentleguide.Repo.Migrations.AddSyncTrackingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :gmail_last_synced_at, :utc_datetime
      add :hubspot_last_synced_at, :utc_datetime
    end

    # Add indexes for efficient querying
    create index(:users, [:gmail_last_synced_at])
    create index(:users, [:hubspot_last_synced_at])
  end
end

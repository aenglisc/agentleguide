defmodule Agentleguide.Repo.Migrations.AddHistoricalSyncCompletedToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :historical_email_sync_completed, :boolean, default: false
    end

    # Add index for efficient querying
    create index(:users, [:historical_email_sync_completed])
  end
end

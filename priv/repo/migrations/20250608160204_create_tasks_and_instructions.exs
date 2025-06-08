defmodule Agentleguide.Repo.Migrations.CreateTasksAndInstructions do
  use Ecto.Migration

  def change do
    # Table for ongoing instructions
    create table(:ongoing_instructions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :is_active, :boolean, default: true
      add :priority, :integer, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:ongoing_instructions, [:user_id])
    create index(:ongoing_instructions, [:user_id, :is_active])

    # Table for tasks
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :status, :string, default: "pending", null: false
      add :priority, :integer, default: 1
      add :context, :map, default: %{}
      add :steps, {:array, :map}, default: []
      add :current_step, :integer, default: 0
      # Could be "ai_agent" or specific service
      add :assigned_to, :string
      add :due_date, :utc_datetime
      add :completed_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:user_id, :status])
    create index(:tasks, [:status])
    create index(:tasks, [:due_date])

    # Table for task execution logs
    create table(:task_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
      add :step_number, :integer
      add :action, :string, null: false
      add :status, :string, null: false
      add :details, :text
      add :metadata, :map, default: %{}
      add :executed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:task_logs, [:task_id])
    create index(:task_logs, [:task_id, :step_number])
  end
end

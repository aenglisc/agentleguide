defmodule Agentleguide.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :priority, :integer, default: 1
    field :context, :map, default: %{}
    field :steps, {:array, :map}, default: []
    field :current_step, :integer, default: 0
    field :assigned_to, :string
    field :due_date, :utc_datetime
    field :completed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, Agentleguide.Accounts.User
    has_many :logs, Agentleguide.Tasks.TaskLog, foreign_key: :task_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :user_id,
      :title,
      :description,
      :status,
      :priority,
      :context,
      :steps,
      :current_step,
      :assigned_to,
      :due_date,
      :completed_at,
      :metadata
    ])
    |> validate_required([:user_id, :title, :status])
    |> validate_inclusion(:status, [
      "pending",
      "in_progress",
      "waiting",
      "completed",
      "failed",
      "cancelled"
    ])
    |> validate_number(:priority, greater_than: 0)
    |> validate_number(:current_step, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end
end

defmodule Agentleguide.Tasks.TaskLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "task_logs" do
    field :step_number, :integer
    field :action, :string
    field :status, :string
    field :details, :string
    field :metadata, :map, default: %{}
    field :executed_at, :utc_datetime

    belongs_to :task, Agentleguide.Tasks.Task

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(task_log, attrs) do
    task_log
    |> cast(attrs, [:task_id, :step_number, :action, :status, :details, :metadata, :executed_at])
    |> put_executed_at()
    |> validate_required([:task_id, :action, :status, :executed_at])
    |> validate_inclusion(:status, ["started", "completed", "failed", "skipped"])
    |> foreign_key_constraint(:task_id)
  end

  defp put_executed_at(changeset) do
    case get_field(changeset, :executed_at) do
      nil -> put_change(changeset, :executed_at, DateTime.truncate(DateTime.utc_now(), :second))
      _ -> changeset
    end
  end
end

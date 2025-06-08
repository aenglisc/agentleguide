defmodule Agentleguide.Tasks do
  @moduledoc """
  The Tasks context.
  Handles task management, ongoing instructions, and task execution.
  """

  import Ecto.Query, warn: false
  alias Agentleguide.Repo
  alias Agentleguide.Tasks.{Task, OngoingInstruction, TaskLog}

  ## Task functions

  @doc """
  Returns the list of tasks for a user.
  """
  def list_tasks(user, filters \\ []) do
    query =
      Task
      |> where([t], t.user_id == ^user.id)
      |> apply_task_filters(filters)
      |> order_by([t], desc: t.inserted_at)

    Repo.all(query)
  end

  @doc """
  Gets a single task.
  """
  def get_task!(id), do: Repo.get!(Task, id)

  @doc """
  Gets a task for a specific user.
  """
  def get_user_task(user, task_id) do
    Task
    |> where([t], t.user_id == ^user.id and t.id == ^task_id)
    |> Repo.one()
  end

  @doc """
  Creates a task.
  """
  def create_task(user, attrs \\ %{}) do
    %Task{}
    |> Task.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates a task.
  """
  def update_task(task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task.
  """
  def delete_task(task) do
    Repo.delete(task)
  end

  @doc """
  Marks a task as completed.
  """
  def complete_task(task) do
    update_task(task, %{
      status: "completed",
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Advances a task to the next step.
  """
  def advance_task_step(task) do
    next_step = task.current_step + 1
    update_task(task, %{current_step: next_step})
  end

  ## OngoingInstruction functions

  @doc """
  Returns active ongoing instructions for a user.
  """
  def list_active_instructions(user) do
    OngoingInstruction
    |> where([oi], oi.user_id == ^user.id and oi.is_active == true)
    |> order_by([oi], desc: oi.priority, asc: oi.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single ongoing instruction.
  """
  def get_instruction!(id), do: Repo.get!(OngoingInstruction, id)

  @doc """
  Creates an ongoing instruction.
  """
  def create_instruction(user, attrs \\ %{}) do
    %OngoingInstruction{}
    |> OngoingInstruction.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates an ongoing instruction.
  """
  def update_instruction(instruction, attrs) do
    instruction
    |> OngoingInstruction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deactivates an ongoing instruction.
  """
  def deactivate_instruction(instruction) do
    update_instruction(instruction, %{is_active: false})
  end

  ## TaskLog functions

  @doc """
  Creates a task log entry.
  """
  def create_task_log(task, attrs \\ %{}) do
    %TaskLog{}
    |> TaskLog.changeset(Map.put(attrs, :task_id, task.id))
    |> Repo.insert()
  end

  @doc """
  Gets logs for a task.
  """
  def get_task_logs(task) do
    TaskLog
    |> where([tl], tl.task_id == ^task.id)
    |> order_by([tl], asc: tl.step_number, asc: tl.executed_at)
    |> Repo.all()
  end

  ## Helper functions

  defp apply_task_filters(query, []), do: query

  defp apply_task_filters(query, [{:status, status} | rest]) do
    query
    |> where([t], t.status == ^status)
    |> apply_task_filters(rest)
  end

  defp apply_task_filters(query, [{:assigned_to, assigned_to} | rest]) do
    query
    |> where([t], t.assigned_to == ^assigned_to)
    |> apply_task_filters(rest)
  end

  defp apply_task_filters(query, [_filter | rest]) do
    apply_task_filters(query, rest)
  end
end

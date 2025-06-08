defmodule Agentleguide.TasksTest do
  use Agentleguide.DataCase

  alias Agentleguide.{Tasks, Accounts}

  describe "tasks" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User"
        })

      %{user: user}
    end

    test "create_task/2 creates a task for user", %{user: user} do
      attrs = %{
        title: "Test Task",
        description: "This is a test task",
        status: "pending"
      }

      assert {:ok, task} = Tasks.create_task(user, attrs)
      assert task.user_id == user.id
      assert task.title == "Test Task"
      assert task.status == "pending"
      assert task.current_step == 0
    end

    test "list_tasks/1 returns tasks for user", %{user: user} do
      {:ok, _task1} = Tasks.create_task(user, %{title: "Task 1", status: "pending"})
      {:ok, _task2} = Tasks.create_task(user, %{title: "Task 2", status: "completed"})

      tasks = Tasks.list_tasks(user)
      assert length(tasks) == 2
    end

    test "list_tasks/2 filters tasks by status", %{user: user} do
      {:ok, _task1} = Tasks.create_task(user, %{title: "Task 1", status: "pending"})
      {:ok, _task2} = Tasks.create_task(user, %{title: "Task 2", status: "completed"})

      pending_tasks = Tasks.list_tasks(user, status: "pending")
      completed_tasks = Tasks.list_tasks(user, status: "completed")

      assert length(pending_tasks) == 1
      assert length(completed_tasks) == 1
      assert hd(pending_tasks).title == "Task 1"
      assert hd(completed_tasks).title == "Task 2"
    end

    test "complete_task/1 marks task as completed", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Task", status: "pending"})

      assert {:ok, completed_task} = Tasks.complete_task(task)
      assert completed_task.status == "completed"
      assert completed_task.completed_at
    end

    test "advance_task_step/1 increments current step", %{user: user} do
      {:ok, task} =
        Tasks.create_task(user, %{
          title: "Multi-step Task",
          steps: [
            %{"action" => "step1", "description" => "First step"},
            %{"action" => "step2", "description" => "Second step"}
          ]
        })

      assert task.current_step == 0

      {:ok, advanced_task} = Tasks.advance_task_step(task)
      assert advanced_task.current_step == 1
    end
  end

  describe "ongoing_instructions" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User"
        })

      %{user: user}
    end

    test "create_instruction/2 creates an ongoing instruction", %{user: user} do
      attrs = %{
        instruction: "When someone emails me, create a contact in HubSpot",
        priority: 2
      }

      assert {:ok, instruction} = Tasks.create_instruction(user, attrs)
      assert instruction.user_id == user.id
      assert instruction.instruction == attrs.instruction
      assert instruction.priority == 2
      assert instruction.is_active == true
    end

    test "list_active_instructions/1 returns only active instructions", %{user: user} do
      {:ok, active1} =
        Tasks.create_instruction(user, %{
          instruction: "Active instruction 1",
          is_active: true
        })

      {:ok, active2} =
        Tasks.create_instruction(user, %{
          instruction: "Active instruction 2",
          is_active: true
        })

      {:ok, inactive} =
        Tasks.create_instruction(user, %{
          instruction: "Inactive instruction",
          is_active: false
        })

      active_instructions = Tasks.list_active_instructions(user)

      assert length(active_instructions) == 2
      instruction_ids = Enum.map(active_instructions, & &1.id)
      assert active1.id in instruction_ids
      assert active2.id in instruction_ids
      refute inactive.id in instruction_ids
    end

    test "deactivate_instruction/1 sets instruction as inactive", %{user: user} do
      {:ok, instruction} =
        Tasks.create_instruction(user, %{
          instruction: "Test instruction",
          is_active: true
        })

      assert {:ok, deactivated} = Tasks.deactivate_instruction(instruction)
      assert deactivated.is_active == false
    end
  end

  describe "task_logs" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User"
        })

      {:ok, task} = Tasks.create_task(user, %{title: "Test Task"})

      %{user: user, task: task}
    end

    test "create_task_log/2 creates a log entry", %{task: task} do
      attrs = %{
        step_number: 1,
        action: "send_email",
        status: "completed",
        details: "Email sent successfully"
      }

      assert {:ok, log} = Tasks.create_task_log(task, attrs)
      assert log.task_id == task.id
      assert log.action == "send_email"
      assert log.status == "completed"
      assert log.executed_at
    end

    test "get_task_logs/1 returns logs for task", %{task: task} do
      {:ok, _log1} =
        Tasks.create_task_log(task, %{
          step_number: 1,
          action: "step1",
          status: "completed"
        })

      {:ok, _log2} =
        Tasks.create_task_log(task, %{
          step_number: 2,
          action: "step2",
          status: "started"
        })

      logs = Tasks.get_task_logs(task)
      assert length(logs) == 2
    end
  end
end

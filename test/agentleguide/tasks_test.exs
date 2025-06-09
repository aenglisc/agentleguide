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

    test "get_task!/1 returns a task by id", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Test Task"})

      retrieved_task = Tasks.get_task!(task.id)
      assert retrieved_task.id == task.id
      assert retrieved_task.title == "Test Task"
    end

    test "get_user_task/2 returns task for specific user", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "User Task"})

      # Create another user to test isolation
      {:ok, other_user} = Accounts.create_user(%{email: "other@example.com", name: "Other User"})

      retrieved_task = Tasks.get_user_task(user, task.id)
      assert retrieved_task.id == task.id

      # Other user should not be able to access this task
      assert Tasks.get_user_task(other_user, task.id) == nil
    end

    test "update_task/2 updates task attributes", %{user: user} do
      {:ok, task} =
        Tasks.create_task(user, %{title: "Original Title", description: "Original Description"})

      updates = %{title: "Updated Title", description: "Updated Description"}
      {:ok, updated_task} = Tasks.update_task(task, updates)

      assert updated_task.title == "Updated Title"
      assert updated_task.description == "Updated Description"
    end

    test "delete_task/1 removes task from database", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "To Delete"})

      assert {:ok, _deleted_task} = Tasks.delete_task(task)

      # Task should no longer exist
      assert_raise Ecto.NoResultsError, fn ->
        Tasks.get_task!(task.id)
      end
    end

    test "list_tasks/2 filters tasks by assigned_to", %{user: user} do
      {:ok, _task1} =
        Tasks.create_task(user, %{title: "Task 1", assigned_to: "alice@example.com"})

      {:ok, _task2} = Tasks.create_task(user, %{title: "Task 2", assigned_to: "bob@example.com"})
      # No assignment
      {:ok, _task3} = Tasks.create_task(user, %{title: "Task 3"})

      alice_tasks = Tasks.list_tasks(user, assigned_to: "alice@example.com")
      bob_tasks = Tasks.list_tasks(user, assigned_to: "bob@example.com")

      assert length(alice_tasks) == 1
      assert length(bob_tasks) == 1
      assert hd(alice_tasks).title == "Task 1"
      assert hd(bob_tasks).title == "Task 2"
    end

    test "list_tasks/2 ignores invalid filters", %{user: user} do
      {:ok, _task1} = Tasks.create_task(user, %{title: "Task 1"})
      {:ok, _task2} = Tasks.create_task(user, %{title: "Task 2"})

      # Should ignore invalid filter and return all tasks
      tasks = Tasks.list_tasks(user, invalid_filter: "value")
      assert length(tasks) == 2
    end

    test "list_tasks/2 handles multiple filters", %{user: user} do
      {:ok, _task1} =
        Tasks.create_task(user, %{
          title: "Task 1",
          status: "pending",
          assigned_to: "alice@example.com"
        })

      {:ok, _task2} =
        Tasks.create_task(user, %{
          title: "Task 2",
          status: "completed",
          assigned_to: "alice@example.com"
        })

      {:ok, _task3} =
        Tasks.create_task(user, %{
          title: "Task 3",
          status: "pending",
          assigned_to: "bob@example.com"
        })

      filtered_tasks = Tasks.list_tasks(user, status: "pending", assigned_to: "alice@example.com")
      assert length(filtered_tasks) == 1
      assert hd(filtered_tasks).title == "Task 1"
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

    test "get_instruction!/1 returns instruction by id", %{user: user} do
      {:ok, instruction} = Tasks.create_instruction(user, %{instruction: "Test instruction"})

      retrieved_instruction = Tasks.get_instruction!(instruction.id)
      assert retrieved_instruction.id == instruction.id
      assert retrieved_instruction.instruction == "Test instruction"
    end

    test "update_instruction/2 updates instruction attributes", %{user: user} do
      {:ok, instruction} =
        Tasks.create_instruction(user, %{
          instruction: "Original instruction",
          priority: 1
        })

      updates = %{instruction: "Updated instruction", priority: 3}
      {:ok, updated_instruction} = Tasks.update_instruction(instruction, updates)

      assert updated_instruction.instruction == "Updated instruction"
      assert updated_instruction.priority == 3
    end

    test "list_active_instructions/1 orders by priority then insertion", %{user: user} do
      # Create instructions with different priorities
      {:ok, low_priority} =
        Tasks.create_instruction(user, %{
          instruction: "Low priority",
          priority: 1,
          is_active: true
        })

      {:ok, high_priority} =
        Tasks.create_instruction(user, %{
          instruction: "High priority",
          priority: 5,
          is_active: true
        })

      {:ok, medium_priority} =
        Tasks.create_instruction(user, %{
          instruction: "Medium priority",
          priority: 3,
          is_active: true
        })

      instructions = Tasks.list_active_instructions(user)

      # Should be ordered by priority descending
      assert length(instructions) == 3
      assert Enum.at(instructions, 0).id == high_priority.id
      assert Enum.at(instructions, 1).id == medium_priority.id
      assert Enum.at(instructions, 2).id == low_priority.id
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

    test "get_task_logs/1 orders logs by step_number and executed_at", %{user: user} do
      {:ok, task} = Tasks.create_task(user, %{title: "Test Task"})

      # Create logs in different order
      {:ok, _log2} =
        Tasks.create_task_log(task, %{
          step_number: 2,
          action: "second_step",
          status: "completed"
        })

      {:ok, _log1a} =
        Tasks.create_task_log(task, %{
          step_number: 1,
          action: "first_step_a",
          status: "completed"
        })

      {:ok, _log1b} =
        Tasks.create_task_log(task, %{
          step_number: 1,
          action: "first_step_b",
          status: "completed"
        })

      logs = Tasks.get_task_logs(task)

      # Should be ordered by step_number first, then by executed_at
      assert length(logs) == 3
      assert Enum.at(logs, 0).step_number == 1
      assert Enum.at(logs, 1).step_number == 1
      assert Enum.at(logs, 2).step_number == 2
      # First created
      assert Enum.at(logs, 0).action == "first_step_a"
      # Second created
      assert Enum.at(logs, 1).action == "first_step_b"
    end

    test "task_logs belong to specific task only", %{user: user} do
      {:ok, task1} = Tasks.create_task(user, %{title: "Task 1"})
      {:ok, task2} = Tasks.create_task(user, %{title: "Task 2"})

      {:ok, _log1} =
        Tasks.create_task_log(task1, %{
          step_number: 1,
          action: "task1_action",
          status: "completed"
        })

      {:ok, _log2} =
        Tasks.create_task_log(task2, %{
          step_number: 1,
          action: "task2_action",
          status: "completed"
        })

      task1_logs = Tasks.get_task_logs(task1)
      task2_logs = Tasks.get_task_logs(task2)

      assert length(task1_logs) == 1
      assert length(task2_logs) == 1
      assert hd(task1_logs).action == "task1_action"
      assert hd(task2_logs).action == "task2_action"
    end
  end
end

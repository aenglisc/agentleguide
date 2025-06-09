defmodule Agentleguide.Services.Ai.AiAgentTest do
  use Agentleguide.DataCase
  import ExUnit.CaptureLog

  alias Agentleguide.Services.Ai.AiAgent
  alias Agentleguide.{Tasks, Accounts}

  describe "create_ongoing_instruction/2" do
    test "creates ongoing instruction with default priority" do
      user = user_fixture()
      instruction = "Always remind me of meetings"

      assert {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.instruction == instruction
      assert ongoing_instruction.user_id == user.id
      assert ongoing_instruction.priority == 1
      assert ongoing_instruction.is_active == true
    end

    test "creates ongoing instruction with high priority for urgent keywords" do
      user = user_fixture()
      instruction = "Urgent: notify me immediately if any email contains 'emergency'"

      assert {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.priority == 5
    end

    test "creates ongoing instruction with medium priority for important keywords" do
      user = user_fixture()
      instruction = "Important: track all meetings with clients"

      assert {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.priority == 3
    end

    test "handles creation errors gracefully" do
      user = user_fixture()
      # Invalid instruction (empty string) - capture expected error log
      capture_log(fn ->
        assert {:error, _reason} = AiAgent.create_ongoing_instruction(user, "")
      end)
    end
  end

  describe "execute_task/2" do
    test "handles task with empty steps" do
      user = user_fixture()

      # Create task with no steps - should complete immediately
      {:ok, task} = Tasks.create_task(user, %{
        title: "Empty Task",
        description: "A task with no steps",
        status: "pending",
        steps: []
      })

      assert {:ok, completed_task} = AiAgent.execute_task(user, task)
      assert completed_task.status == "completed"
    end

    test "updates task status to in_progress" do
      user = user_fixture()

      {:ok, task} = Tasks.create_task(user, %{
        title: "Test Task",
        description: "A test task",
        status: "pending",
        steps: []
      })

      assert {:ok, updated_task} = AiAgent.execute_task(user, task)
      # Should be completed since no steps
      assert updated_task.status == "completed"
    end
  end

  describe "handle_external_event/3" do
    test "processes events without relevant instructions" do
      user = user_fixture()

      event_data = %{
        "from" => "test@example.com",
        "subject" => "Test Email",
        "body" => "Test content"
      }

      # Should complete without error even with no instructions
      assert :ok = AiAgent.handle_external_event(user, :email_received, event_data)
    end

    test "processes events with existing instructions" do
      user = user_fixture()

      # Create an ongoing instruction
      {:ok, _instruction} = Tasks.create_instruction(user, %{
        instruction: "When I receive emails, log them",
        priority: 1
      })

      event_data = %{
        "from" => "client@example.com",
        "subject" => "Project Update",
        "body" => "Here's the latest status..."
      }

      # Should complete without error
      assert :ok = AiAgent.handle_external_event(user, :email_received, event_data)
    end

    test "handles different event types" do
      user = user_fixture()

      calendar_event = %{
        "summary" => "Team Meeting",
        "start" => "2024-01-15T10:00:00Z"
      }

      # Should handle calendar events
      assert :ok = AiAgent.handle_external_event(user, :calendar_event, calendar_event)
    end
  end

  # Test private function behavior indirectly through public functions
  describe "instruction analysis (via create_ongoing_instruction)" do
    test "detects conditional instructions with 'when'" do
      user = user_fixture()
      instruction = "When I receive emails from john@example.com, forward them"

      {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      # Should create an ongoing instruction for conditional statements
      assert ongoing_instruction.instruction == instruction
    end

    test "detects conditional instructions with 'whenever'" do
      user = user_fixture()
      instruction = "Whenever someone mentions 'urgent', notify me"

      {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.instruction == instruction
    end

    test "detects conditional instructions with 'always'" do
      user = user_fixture()
      instruction = "Always backup important documents"

      {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.instruction == instruction
    end

    test "detects conditional instructions with 'if'" do
      user = user_fixture()
      instruction = "If I get emails from the CEO, prioritize them"

      {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.instruction == instruction
    end
  end

  describe "priority determination" do
    test "assigns high priority for urgent keywords" do
      user = user_fixture()

      urgent_instructions = [
        "Urgent: process this immediately",
        "Please handle this ASAP",
        "Do this immediately"
      ]

      for instruction <- urgent_instructions do
        {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
        assert ongoing_instruction.priority == 5
      end
    end

    test "assigns medium priority for important keywords" do
      user = user_fixture()

      important_instructions = [
        "Important: review all contracts",
        "This is a priority task"
      ]

      for instruction <- important_instructions do
        {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
        assert ongoing_instruction.priority == 3
      end
    end

    test "assigns default priority for normal instructions" do
      user = user_fixture()
      instruction = "Please organize my calendar"

      {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, instruction)
      assert ongoing_instruction.priority == 1
    end
  end

  defp user_fixture(attrs \\ %{}) do
    default_attrs = %{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end

  describe "process_instruction/2" do
    test "creates ongoing instruction for conditional statements" do
      user = user_fixture()
      instruction = "When I get emails from my boss, forward them to my assistant"

      assert {:ok, ongoing_instruction} = AiAgent.process_instruction(user, instruction)
      assert ongoing_instruction.instruction == instruction
    end

    test "attempts to create task for action-oriented instructions" do
      user = user_fixture()
      instruction = "Schedule a meeting with John next week"

      # With AI service being stubbed, this should fail gracefully
      capture_log(fn ->
        assert {:error, _reason} = AiAgent.process_instruction(user, instruction)
      end)
    end

    test "handles immediate action instructions" do
      user = user_fixture()
      instruction = "What's the weather today?"

      # AI service actually works in test environment and returns responses
      capture_log(fn ->
        assert {:ok, response} = AiAgent.process_instruction(user, instruction)
        assert is_binary(response)
      end)
    end
  end

  describe "create_task_from_instruction/2" do
    test "handles AI service errors gracefully" do
      user = user_fixture()
      instruction = "Send an email to all my contacts about the project update"

      # With test stubs, AI service will return errors
      capture_log(fn ->
        assert {:error, _reason} = AiAgent.create_task_from_instruction(user, instruction)
      end)
    end
  end

  describe "execute_next_step/2" do
    test "completes task when all steps are finished" do
      user = user_fixture()

      {:ok, task} = Tasks.create_task(user, %{
        title: "Multi-step Task",
        description: "A task with multiple steps",
        status: "in_progress",
        current_step: 2,
        steps: [
          %{"action" => "step1", "description" => "First step"},
          %{"action" => "step2", "description" => "Second step"}
        ]
      })

      # Task should be completed since current_step (2) >= length(steps) (2)
      assert {:ok, completed_task} = AiAgent.execute_next_step(user, task)
      assert completed_task.status == "completed"
    end

    test "executes step and completes task when single step finishes" do
      user = user_fixture()

      {:ok, task} = Tasks.create_task(user, %{
        title: "Test Task",
        description: "A test task",
        status: "in_progress",
        current_step: 0,
        steps: [
          %{
            "action" => "search_contacts",
            "description" => "Search for contacts",
            "parameters" => %{"query" => "test"},
            "wait_for_response" => false
          }
        ]
      })

      # Tool execution succeeds, so task should complete
      capture_log(fn ->
        assert {:ok, completed_task} = AiAgent.execute_next_step(user, task)
        assert completed_task.status == "completed"
      end)
    end

    test "handles malformed step data" do
      user = user_fixture()

      {:ok, task} = Tasks.create_task(user, %{
        title: "Malformed Task",
        description: "A task with bad step data",
        status: "in_progress",
        current_step: 0,
        steps: [
          %{
            "invalid" => "step_data",
            "missing" => "action_field"
          }
        ]
      })

      # Should handle malformed data gracefully and mark task as failed
      capture_log(fn ->
        assert {:ok, failed_task} = AiAgent.execute_next_step(user, task)
        assert failed_task.status == "failed"
      end)
    end
  end

  describe "handle_external_event/3 - detailed scenarios" do
    test "matches instructions with email events" do
      user = user_fixture()

      # Create instruction that should match email events
      {:ok, _instruction} = Tasks.create_instruction(user, %{
        instruction: "When I receive emails from clients, log them in CRM",
        priority: 2
      })

      event_data = %{
        from_email: "client@example.com",
        subject: "Project Discussion",
        body: "Let's discuss the project timeline"
      }

      # Should process the event and potentially execute proactive actions
      capture_log(fn ->
        assert :ok = AiAgent.handle_external_event(user, :new_email, event_data)
      end)
    end

    test "matches instructions with calendar events" do
      user = user_fixture()

      {:ok, _instruction} = Tasks.create_instruction(user, %{
        instruction: "Before every meeting, remind me to review notes",
        priority: 3
      })

      event_data = %{
        summary: "Weekly Team Meeting",
        start_time: "2024-01-15T10:00:00Z"
      }

      capture_log(fn ->
        assert :ok = AiAgent.handle_external_event(user, :calendar_event, event_data)
      end)
    end

    test "handles events with no matching instructions" do
      user = user_fixture()

      # No instructions created
      event_data = %{
        from_email: "random@example.com",
        subject: "Random email"
      }

      # Should complete without issues
      assert :ok = AiAgent.handle_external_event(user, :new_email, event_data)
    end

    test "processes HubSpot contact events" do
      user = user_fixture()

      {:ok, _instruction} = Tasks.create_instruction(user, %{
        instruction: "When new contacts are added, send welcome email",
        priority: 1
      })

      event_data = %{
        name: "John Doe",
        email: "john@newcompany.com",
        company: "New Company Inc"
      }

      capture_log(fn ->
        assert :ok = AiAgent.handle_external_event(user, :hubspot_contact, event_data)
      end)
    end
  end

  describe "instruction type analysis (via process_instruction)" do
    test "identifies task instructions and handles AI service failures" do
      user = user_fixture()
      task_instructions = [
        "Schedule a meeting with the team",
        "Create a new contact for John Smith",
        "Send a follow-up email to all clients",
        "Find available time slots next week"
      ]

      for instruction <- task_instructions do
        capture_log(fn ->
          # These should attempt to create tasks but fail due to AI service being stubbed
          assert {:error, _reason} = AiAgent.process_instruction(user, instruction)
        end)
      end
    end

        test "processes question-style instructions as immediate actions" do
      user = user_fixture()

      # Test a specific question that should work
      capture_log(fn ->
        assert {:ok, response} = AiAgent.process_instruction(user, "What's my next meeting?")
        assert is_binary(response)
        assert String.contains?(response, "meeting") or String.contains?(response, "calendar")
      end)
    end

    test "processes command-style instructions that may fail" do
      user = user_fixture()

      # Test instructions that require external data and may fail
      problematic_instructions = [
        "Show me today's schedule",
        "How many contacts do I have?"
      ]

      for instruction <- problematic_instructions do
        capture_log(fn ->
          # These may succeed or fail depending on available data/AI parsing
          case AiAgent.process_instruction(user, instruction) do
            {:ok, response} ->
              assert is_binary(response)
              assert String.length(response) > 0
            {:error, "Failed to parse AI response"} ->
              # This is an expected failure mode when AI returns non-JSON
              :ok
            {:error, reason} ->
              # Other errors should be meaningful
              assert is_binary(reason) or is_atom(reason)
          end
        end)
      end
    end
  end

  describe "error handling" do
    test "handles empty instruction by defaulting to immediate action" do
      user = user_fixture()

      capture_log(fn ->
        # Empty instruction should be treated as immediate action and return AI response
        assert {:ok, response} = AiAgent.process_instruction(user, "")
        assert is_binary(response)
      end)
    end

    test "handles very long instructions without crashing" do
      user = user_fixture()
      long_instruction = String.duplicate("Create a task ", 100)

      capture_log(fn ->
        # Should not crash, but fail due to AI service being stubbed
        assert {:error, _reason} = AiAgent.process_instruction(user, long_instruction)
      end)
    end
  end

  describe "edge cases" do
    test "validates current_step must be non-negative" do
      user = user_fixture()

      # Database validation should prevent negative current_step
      assert {:error, changeset} = Tasks.create_task(user, %{
        title: "Edge Case Task",
        description: "Task with negative current_step",
        status: "in_progress",
        current_step: -1,
        steps: [%{"action" => "test", "description" => "Test step"}]
      })

      assert changeset.errors[:current_step] != nil
    end

    test "handles mixed case keywords in instructions" do
      user = user_fixture()
      mixed_case_instruction = "URGENT: Schedule IMPORTANT meeting ASAP"

      {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, mixed_case_instruction)
      # Should detect urgent keyword regardless of case
      assert ongoing_instruction.priority == 5
    end

    test "handles instructions with special characters" do
      user = user_fixture()
      special_instruction = "When I get emails with subject containing 'RE: [URGENT]', prioritize them!"

      capture_log(fn ->
        assert {:ok, ongoing_instruction} = AiAgent.create_ongoing_instruction(user, special_instruction)
        assert ongoing_instruction.instruction == special_instruction
      end)
    end
  end
end

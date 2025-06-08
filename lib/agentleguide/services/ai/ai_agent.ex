defmodule Agentleguide.Services.Ai.AiAgent do
  @moduledoc """
  Main AI agent that handles ongoing instructions, task execution, and proactive actions.
  Coordinates with various services to provide intelligent automation.
  """

  require Logger
  alias Agentleguide.Tasks
  alias Agentleguide.Services.Ai.{AiService, AiTools}

  @doc """
  Process user instruction and potentially create ongoing instructions or tasks.
  """
  def process_instruction(user, instruction) do
    # Analyze if this is an ongoing instruction or a one-time task
    case analyze_instruction_type(instruction) do
      :ongoing ->
        create_ongoing_instruction(user, instruction)

      :task ->
        create_task_from_instruction(user, instruction)

      :immediate ->
        execute_immediate_action(user, instruction)
    end
  end

  @doc """
  Create an ongoing instruction that will be considered for future events.
  """
  def create_ongoing_instruction(user, instruction) do
    case Tasks.create_instruction(user, %{
           instruction: instruction,
           priority: determine_priority(instruction)
         }) do
      {:ok, ongoing_instruction} ->
        Logger.info("Created ongoing instruction for user #{user.id}: #{instruction}")
        {:ok, ongoing_instruction}

      {:error, reason} ->
        Logger.error("Failed to create ongoing instruction: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Create a task from an instruction that requires multiple steps.
  """
  def create_task_from_instruction(user, instruction) do
    # Use AI to break down the instruction into steps
    case generate_task_steps(user, instruction) do
      {:ok, %{"title" => title, "steps" => steps}} ->
        task_attrs = %{
          title: title,
          description: instruction,
          status: "pending",
          steps: steps,
          assigned_to: "ai_agent",
          context: %{
            "original_instruction" => instruction,
            "created_by" => "ai_agent"
          }
        }

        case Tasks.create_task(user, task_attrs) do
          {:ok, task} ->
            Logger.info("Created task for user #{user.id}: #{title}")
            # Start executing the task
            execute_task(user, task)

          {:error, reason} ->
            Logger.error("Failed to create task: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute a task by going through its steps.
  """
  def execute_task(user, task) do
    case Tasks.update_task(task, %{status: "in_progress"}) do
      {:ok, updated_task} ->
        execute_next_step(user, updated_task)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute the next step of a task.
  """
  def execute_next_step(user, task) do
    if task.current_step < length(task.steps) do
      current_step_data = Enum.at(task.steps, task.current_step)

      # Log step start
      Tasks.create_task_log(task, %{
        step_number: task.current_step + 1,
        action: current_step_data["action"],
        status: "started",
        details: "Starting step: #{current_step_data["description"]}"
      })

      case execute_step_action(user, task, current_step_data) do
        {:ok, result} ->
          # Log step completion
          Tasks.create_task_log(task, %{
            step_number: task.current_step + 1,
            action: current_step_data["action"],
            status: "completed",
            details: "Step completed successfully",
            metadata: %{"result" => result}
          })

          # Advance to next step
          {:ok, updated_task} = Tasks.advance_task_step(task)

          # Check if we need to wait or continue
          if current_step_data["wait_for_response"] do
            Tasks.update_task(updated_task, %{status: "waiting"})
          else
            execute_next_step(user, updated_task)
          end

        {:error, reason} ->
          # Log step failure
          Tasks.create_task_log(task, %{
            step_number: task.current_step + 1,
            action: current_step_data["action"],
            status: "failed",
            details: "Step failed: #{inspect(reason)}"
          })

          Tasks.update_task(task, %{status: "failed"})
      end
    else
      # Task completed
      Tasks.complete_task(task)
    end
  end

  @doc """
  Handle proactive actions based on external events (emails, calendar changes, etc.).
  """
  def handle_external_event(user, event_type, event_data) do
    # Get active ongoing instructions
    instructions = Tasks.list_active_instructions(user)

    # Use AI to determine if any instructions apply to this event
    relevant_instructions = filter_relevant_instructions(instructions, event_type, event_data)

    # Execute relevant instructions
    Enum.each(relevant_instructions, fn instruction ->
      execute_proactive_action(user, instruction, event_type, event_data)
    end)
  end

  # Private functions

  defp analyze_instruction_type(instruction) do
    instruction_lower = String.downcase(instruction)

    cond do
      String.contains?(instruction_lower, ["when", "whenever", "always", "if"]) ->
        :ongoing

      String.contains?(instruction_lower, ["schedule", "create", "send", "find"]) ->
        :task

      true ->
        :immediate
    end
  end

  defp determine_priority(instruction) do
    instruction_lower = String.downcase(instruction)

    cond do
      String.contains?(instruction_lower, ["urgent", "asap", "immediately"]) -> 5
      String.contains?(instruction_lower, ["important", "priority"]) -> 3
      true -> 1
    end
  end

  defp generate_task_steps(user, instruction) do
    system_prompt = """
    You are an AI assistant that breaks down user instructions into actionable steps.

    Given a user instruction, create a JSON response with:
    - "title": A short title for the task
    - "steps": An array of step objects with:
      - "action": The action to perform (e.g., "search_contacts", "send_email", "schedule_meeting")
      - "description": Human-readable description
      - "parameters": Parameters needed for the action
      - "wait_for_response": Boolean indicating if we should wait for external response

    Available actions: search_contacts, send_email, get_available_time_slots, schedule_meeting, create_hubspot_contact, get_upcoming_events

    Instruction: #{instruction}
    """

    case AiService.chat_completion(
           [
             %{"role" => "system", "content" => system_prompt},
             %{"role" => "user", "content" => instruction}
           ],
           [],
           user
         ) do
      {:ok, response} ->
        case Jason.decode(response) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, "Failed to parse AI response"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_immediate_action(user, instruction) do
    # For immediate actions, we can use the existing chat completion with tools
    AiService.chat_completion(
      [
        %{"role" => "user", "content" => instruction}
      ],
      [],
      user
    )
  end

  defp execute_step_action(user, _task, step_data) do
    action = step_data["action"]
    parameters = step_data["parameters"] || %{}

    AiTools.execute_tool_call(user, action, parameters)
  end

  defp filter_relevant_instructions(instructions, event_type, event_data) do
    # This is a simplified implementation
    # In a real system, you'd use more sophisticated NLP to match instructions to events

    event_keywords = extract_event_keywords(event_type, event_data)

    Enum.filter(instructions, fn instruction ->
      instruction_keywords = String.split(String.downcase(instruction.instruction))

      Enum.any?(event_keywords, fn keyword ->
        keyword in instruction_keywords
      end)
    end)
  end

  defp extract_event_keywords(event_type, event_data) do
    case event_type do
      :new_email ->
        ["email", "message", "contact", event_data[:from_email] || ""]

      :calendar_event ->
        ["calendar", "meeting", "appointment", "event"]

      :hubspot_contact ->
        ["contact", "hubspot", "crm", event_data[:name] || ""]

      _ ->
        []
    end
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&(String.length(&1) > 2))
  end

  defp execute_proactive_action(user, instruction, event_type, event_data) do
    # Create a context-aware prompt for the AI
    context_prompt = build_proactive_context(instruction.instruction, event_type, event_data)

    case AiService.chat_completion(
           [
             %{"role" => "system", "content" => context_prompt},
             %{
               "role" => "user",
               "content" =>
                 "Execute the appropriate action based on the ongoing instruction and current event."
             }
           ],
           [],
           user
         ) do
      {:ok, _response} ->
        Logger.info("Executed proactive action for instruction: #{instruction.instruction}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to execute proactive action: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_proactive_context(instruction, event_type, event_data) do
    """
    You have an ongoing instruction: "#{instruction}"

    A new event has occurred:
    Event Type: #{event_type}
    Event Data: #{Jason.encode!(event_data)}

    Based on the ongoing instruction and this event, determine if you should take any action.
    If so, use the available tools to perform the appropriate action.
    If no action is needed, respond with "No action required."
    """
  end
end

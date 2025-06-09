defmodule Agentleguide.Services.Ai.AiService do
  @moduledoc """
  Service for interacting with AI APIs.
  Supports multiple backends: OpenAI, Ollama (local), and Mock (testing).
  """

  require Logger

  # Configuration
  @openai_chat_model "gpt-4o-mini"
  @openai_embedding_model "text-embedding-3-small"
  @ollama_chat_model "llama3.2:latest"
  @ollama_embedding_model "rjmalagon/gte-qwen2-1.5b-instruct-embed-f16"

  # Get the configured backend
  defp backend do
    Application.get_env(:agentleguide, :ai_backend, :openai)
  end

  defp ollama_url do
    Application.get_env(:agentleguide, :ollama_url, "http://localhost:11434")
  end

  @doc """
  Generate embeddings for the given text using the configured AI backend.
  """
  def generate_embeddings(text) do
    # Check if embeddings are enabled
    if Application.get_env(:agentleguide, :embeddings_enabled, true) do
      case backend() do
        :openai -> generate_openai_embeddings(text)
        :ollama -> generate_ollama_embeddings(text)
      end
    else
      Logger.debug("Embeddings disabled in configuration")
      {:error, "Embeddings disabled"}
    end
  end

  @doc """
  Generate a chat completion with context from RAG and tool calling support.
  """
  def chat_completion(messages, context \\ [], user \\ nil) do
    case backend() do
      :openai -> openai_chat_completion(messages, context, user)
      :ollama -> ollama_chat_completion(messages, context, user)
    end
  end

  # OpenAI Implementation
  defp generate_openai_embeddings(text) do
    case OpenAI.embeddings(
           model: @openai_embedding_model,
           input: text
         ) do
      {:ok, %{data: [%{"embedding" => embedding}]}} ->
        {:ok, embedding}

      {:error, error} ->
        Logger.error("Failed to generate OpenAI embeddings: #{inspect(error)}")
        {:error, error}
    end
  end

  defp openai_chat_completion(messages, context, user) do
    system_message = build_system_message(context)
    all_messages = [system_message | messages]

    # Add tools if user is provided
    tools = if user, do: Agentleguide.Services.Ai.AiTools.get_available_tools(), else: nil

    request_params = %{
      model: @openai_chat_model,
      messages: all_messages,
      temperature: 0.7,
      max_tokens: 1000
    }

    request_params = if tools, do: Map.put(request_params, :tools, tools), else: request_params

    case OpenAI.chat_completion(request_params) do
      {:ok, %{choices: [%{"message" => message} | _]}} ->
        handle_openai_response(message, user)

      {:error, error} ->
        Logger.error("Failed to generate OpenAI chat completion: #{inspect(error)}")
        {:error, error}
    end
  end

  defp handle_openai_response(%{"content" => content}, _user) when is_binary(content) do
    {:ok, content}
  end

  defp handle_openai_response(%{"tool_calls" => tool_calls}, user) when is_list(tool_calls) do
    # Execute tool calls
    tool_results =
      Enum.map(tool_calls, fn tool_call ->
        %{"function" => %{"name" => function_name, "arguments" => arguments_json}} = tool_call

        case Jason.decode(arguments_json) do
          {:ok, arguments} ->
            case Agentleguide.Services.Ai.AiTools.execute_tool_call(user, function_name, arguments) do
              {:ok, result} ->
                "Tool #{function_name} executed successfully: #{Jason.encode!(result)}"

              {:error, error} ->
                "Tool #{function_name} failed: #{error}"
            end

          {:error, _} ->
            "Failed to parse arguments for tool #{function_name}"
        end
      end)

    result_text = Enum.join(tool_results, "\n\n")
    {:ok, result_text}
  end

  defp handle_openai_response(message, _user) do
    Logger.warning("Unexpected OpenAI response format: #{inspect(message)}")
    {:ok, "I encountered an unexpected response format. Please try again."}
  end

  # Ollama Implementation
  defp generate_ollama_embeddings(text) do
    request_body = %{
      "model" => @ollama_embedding_model,
      "prompt" => text
    }

    headers = [
      {"Content-Type", "application/json"}
    ]

    case Finch.build(
           :post,
           "#{ollama_url()}/api/embeddings",
           headers,
           Jason.encode!(request_body)
         )
         |> Finch.request(Agentleguide.Finch, receive_timeout: 30_000, request_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"embedding" => embedding}} ->
            {:ok, embedding}

          {:error, error} ->
            Logger.error("Failed to parse Ollama embedding response: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %{status: 404, body: _body}} ->
        Logger.error(
          "Ollama embedding model not found: #{@ollama_embedding_model}. Please run `ollama pull #{@ollama_embedding_model}`."
        )

        {:error,
         "Ollama embedding model not found. Make sure you have pulled it with `ollama pull #{@ollama_embedding_model}`"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama embedding API error (#{status}): #{body}")
        {:error, "Ollama embedding API error: #{status}"}

      {:error, error} ->
        Logger.error("Failed to connect to Ollama for embeddings: #{inspect(error)}")
        {:error, "Failed to connect to Ollama. Is it running?"}
    end
  end

  defp ollama_chat_completion(messages, context, user) do
    Logger.info("🔧 Ollama chat completion called. User: #{if user, do: "#{user.id}", else: "nil"}")
    system_message = build_system_message(context)

    # If user is provided, add tool-calling capability to system message
    enhanced_system_message =
      if user do
        Logger.info("✅ Adding tool instructions to system message for user #{user.id}")
        enhance_system_message_with_tools(system_message)
      else
        Logger.info("❌ No user provided - tools will not be available")
        system_message
      end

    all_messages = [enhanced_system_message | messages]

    # Convert messages to Ollama format
    ollama_messages =
      Enum.map(all_messages, fn msg ->
        %{
          "role" => msg["role"],
          "content" => msg["content"]
        }
      end)

    request_body = %{
      "model" => @ollama_chat_model,
      "messages" => ollama_messages,
      "stream" => false,
      "options" => %{
        "temperature" => 0.7,
        "num_predict" => 1000
      }
    }

    headers = [
      {"Content-Type", "application/json"}
    ]

    case Finch.build(:post, "#{ollama_url()}/api/chat", headers, Jason.encode!(request_body))
         |> Finch.request(Agentleguide.Finch, receive_timeout: 60_000, request_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"message" => %{"content" => content}}} ->
            # Process the response to detect and execute tool calls
            process_ollama_response_for_tools(content, user)

          {:error, error} ->
            Logger.error("Failed to parse Ollama response: #{inspect(error)}")
            {:error, error}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("Ollama API error (#{status}): #{body}")
        {:error, "Ollama API error: #{status}"}

      {:error, error} ->
        Logger.error("Failed to connect to Ollama: #{inspect(error)}")
        {:error, "Failed to connect to Ollama. Is it running?"}
    end
  end

  # Enhanced system message that includes available tools
  defp enhance_system_message_with_tools(system_message) do
    tools_description = """

        You have access to the following tools:
    1. search_contacts(query) - Search for EXISTING contacts by name, email, or company. OPTIONAL query parameter - if no query provided, returns ALL contacts (use for counting customers)
    2. search_emails - Search through Gmail emails. Use these parameters:
       - sender: Use this when searching for emails FROM a specific person (e.g., "emails from John")
       - query: Use this when searching email content, subjects, or general keywords
       - limit: Maximum number of emails to return (default: 10)
    3. send_email - Send an email. REQUIRED parameters: to_email, subject, body
    4. get_available_time_slots - Get available calendar time slots. REQUIRED: start_date, end_date (YYYY-MM-DD format)
    5. schedule_meeting - Schedule a meeting. Parameters: contact_email, datetime, duration, subject
    6. create_hubspot_contact - Create a NEW contact. Parameters: email, first_name, last_name, company, phone
    7. get_upcoming_events - Get upcoming calendar events. Optional: days_ahead (default: 7)

    TOOL SELECTION RULES:
    - "find/search contact" → use search_contacts (for EXISTING contacts)
    - "create/add contact" → use create_hubspot_contact (for NEW contacts)
    - "emails from [person]" → use search_emails with sender parameter
    - "emails about [topic]" → use search_emails with query parameter
    - "who asked me about [topic]?" → use search_emails with query parameter
    - "who emailed me about [topic]?" → use search_emails with query parameter
    - "how many customers/contacts do I have?" → use search_contacts with no parameters
    - "send email" → use send_email (MUST include to_email, subject, AND body)

    EXAMPLES:
    - "how many customers do I have?" → TOOL_CALL: search_contacts, PARAMETERS: {}
    - "list all contacts" → TOOL_CALL: search_contacts, PARAMETERS: {}
    - "search for John" → TOOL_CALL: search_contacts, PARAMETERS: {"query": "John"}
    - "emails from John" → TOOL_CALL: search_emails, PARAMETERS: {"sender": "John"}
    - "newest email from Sarah" → TOOL_CALL: search_emails, PARAMETERS: {"sender": "Sarah", "limit": 1}
    - "emails about golf" → TOOL_CALL: search_emails, PARAMETERS: {"query": "golf"}
    - "who asked me to play golf?" → TOOL_CALL: search_emails, PARAMETERS: {"query": "golf"}
    - "who emailed me about the meeting?" → TOOL_CALL: search_emails, PARAMETERS: {"query": "meeting"}
    - "recent emails" → TOOL_CALL: search_emails, PARAMETERS: {"limit": 10}
    - "send email to john@test.com" → TOOL_CALL: send_email, PARAMETERS: {"to_email": "john@test.com", "subject": "...", "body": "..."}
    - "create contact John Smith" → TOOL_CALL: create_hubspot_contact, PARAMETERS: {"email": "john@example.com", "first_name": "John", "last_name": "Smith"}
    - "time slots for next week" → TOOL_CALL: get_available_time_slots, PARAMETERS: {"start_date": "2025-06-09", "end_date": "2025-06-15"}
    - "upcoming events" → TOOL_CALL: get_upcoming_events, PARAMETERS: {"days_ahead": 7}

    When you need to use a tool, respond with this exact format:
    TOOL_CALL: tool_name
    PARAMETERS: {"param1": "value1", "param2": "value2"}

    CRITICAL JSON RULES:
    - ALL parameter names MUST be in double quotes: "to_email", "subject", "body"
    - ALL string values MUST be in double quotes: "john@example.com", "Test Subject"
    - Numbers can be unquoted: 7, 10
    - Use null (not None), true (not True), false (not False)
    - NEVER use formats like "TO EMAIL:" or "SUBJECT:" - always use PARAMETERS with proper JSON
    - Include ALL required parameters (especially "body" for send_email)

    CORRECT EXAMPLES:
    TOOL_CALL: search_emails
    PARAMETERS: {"sender": "Roman", "limit": 1}

    TOOL_CALL: send_email
    PARAMETERS: {"to_email": "john@example.com", "subject": "Test Subject", "body": "Hello John, how are you?"}

    TOOL_CALL: create_hubspot_contact
    PARAMETERS: {"email": "jane@company.com", "first_name": "Jane", "last_name": "Doe", "company": "Company Inc."}

    After the tool executes, I'll provide the result and you can continue the conversation normally.
    """

    %{
      "role" => "system",
      "content" => system_message["content"] <> tools_description
    }
  end

  # Process Ollama response to detect and execute tool calls
  defp process_ollama_response_for_tools(content, user)
       when is_binary(content) and not is_nil(user) do
    Logger.info("🔍 Processing Ollama response for user #{user.id}. Content length: #{String.length(content)}")
    Logger.debug("📝 Ollama response content: #{content}")

    case parse_tool_call_from_content(content) do
      {:tool_call, tool_name, parameters} ->
        Logger.info("✅ TOOL_CALL detected: #{tool_name} with params: #{inspect(parameters)}")
        # Execute the tool call
        case Agentleguide.Services.Ai.AiTools.execute_tool_call(user, tool_name, parameters) do
          {:ok, result} ->
            Logger.info("Tool #{tool_name} executed successfully for user #{user.id}")
            Logger.debug("Tool #{tool_name} result: #{inspect(result)}")
            result_text = "I executed #{tool_name} successfully. " <> format_tool_result(result)
            {:ok, result_text}

          {:error, error} ->
            Logger.error("Tool #{tool_name} failed for user #{user.id}: #{inspect(error)}")
            {:ok, "I tried to #{tool_name} but encountered an error: #{error}"}
        end

      :no_tool_call ->
        Logger.info("❌ No TOOL_CALL detected in response")
        {:ok, content}

      :parse_error ->
        Logger.error("❌ TOOL_CALL parsing error")
        {:ok, content}
    end
  end

    defp process_ollama_response_for_tools(content, _user) do
    {:ok, content}
  end

  # Parse tool call from Ollama's text response
  defp parse_tool_call_from_content(content) do
    # Look for TOOL_CALL: and PARAMETERS: patterns
    case Regex.run(~r/TOOL_CALL:\s*(\w+)\s*\nPARAMETERS:\s*(\{.*?\})/s, content) do
      [_, tool_name, parameters_json] ->
        # Try to fix common JSON formatting issues before parsing
        fixed_json = fix_json_formatting(parameters_json)

        case Jason.decode(fixed_json) do
          {:ok, parameters} ->
            {:tool_call, tool_name, parameters}

          {:error, _} ->
            :parse_error
        end

      nil ->
        :no_tool_call
    end
  end

  # Fix common JSON formatting issues from Ollama
  defp fix_json_formatting(json_str) do
    json_str
    # Fix unquoted parameter names like: limit": 1 -> "limit": 1
    |> String.replace(~r/(\s|^|,)([a-zA-Z_][a-zA-Z0-9_]*)":\s*/, "\\1\"\\2\": ")
    # Fix Python-style None/True/False values
    |> String.replace(~r/:\s*None\b/, ": null")
    |> String.replace(~r/:\s*True\b/, ": true")
    |> String.replace(~r/:\s*False\b/, ": false")
    # Remove any trailing commas before closing braces
    |> String.replace(~r/,\s*}/, "}")
  end

  # Format tool results for natural language response
  defp format_tool_result(result) when is_map(result) do
    case result do
      %{"status" => "sent", "message" => message} ->
        message

      %{"contacts" => contacts, "count" => count} when count > 0 ->
        if count <= 5 do
          # For small lists, show the contacts
          contact_list =
            Enum.map_join(contacts, ", ", fn contact ->
              "#{contact["name"]} (#{contact["email"]})"
            end)

          "Here are the #{count} contacts I found: #{contact_list}"
        else
          # For larger lists (like counting all customers), just show the count
          "You have #{count} contacts/customers in your system."
        end

      %{"contacts" => [], "count" => 0} ->
        "I didn't find any contacts matching that search."

      %{"emails" => emails, "count" => count} when count > 0 ->
        email_list =
          Enum.map_join(emails, "\n\n", fn email ->
            date_str = if email["date"], do: " on #{email["date"]}", else: ""

            "• From: #{email["from_name"] || email["from_email"]}#{date_str}\n  Subject: #{email["subject"]}\n  Preview: #{email["snippet"]}..."
          end)

        "I found #{count} email(s):\n\n#{email_list}"

      %{"emails" => [], "count" => 0} ->
        Logger.info("Email search returned zero results - correctly reporting no matches found")
        "I didn't find any emails matching that search."

      %{"events" => events} when is_list(events) ->
        if Enum.empty?(events) do
          "No upcoming events found."
        else
          event_list =
            Enum.map_join(events, ", ", fn event ->
              event["summary"] || "Event"
            end)

          "Here are the upcoming events: #{event_list}"
        end

      _ ->
        "Result: #{Jason.encode!(result)}"
    end
  end

  defp format_tool_result(result) do
    "Result: #{inspect(result)}"
  end

  # Build context-aware system message for the AI assistant.
  defp build_system_message(context) when is_list(context) do
    base_prompt = """
    You are an AI assistant for a financial advisor. Your role is to help answer questions about clients using information from emails and HubSpot CRM records.

    CRITICAL RULES - NEVER VIOLATE:
    1. NEVER make up or invent email data, contact information, or any other information
    2. ONLY use real data from actual tool executions
    3. If a tool returns empty results, say "no results found" - DO NOT create fake examples
    4. NEVER respond as if you executed a tool without actually using the TOOL_CALL format first
    5. BEFORE saying "I don't have information", ALWAYS check if you can use a tool to find the answer
    6. Questions about "who asked/emailed about X" should ALWAYS use search_emails with the topic as query

    Key instructions:
    1. Always base your answers on the provided context from emails and client records
    2. If you don't have enough information to answer a question, say so clearly
    3. When mentioning specific information, try to reference the source (email, contact record, note)
    4. Be professional and helpful
    5. If a person's name is ambiguous, ask for clarification about which person they're referring to
    6. Focus on providing actionable insights for the financial advisor

    """

    context_text =
      case context do
        [] ->
          "No specific context provided for this query."

        context_items ->
          context_items
          |> Enum.with_index(1)
          |> Enum.map(fn {item, idx} ->
            "#{idx}. #{format_context_item(item)}"
          end)
          |> Enum.join("\n\n")
      end

    full_prompt = base_prompt <> "\n\nRelevant context:\n" <> context_text

    %{
      "role" => "system",
      "content" => full_prompt
    }
  end

  defp format_context_item(%{document_type: "gmail_email", content: content, metadata: metadata}) do
    from = get_in(metadata, ["from_email"]) || "Unknown"
    from_name = get_in(metadata, ["from_name"]) || from
    subject = get_in(metadata, ["subject"]) || "No subject"

    display_from = if from_name != from, do: "#{from_name} <#{from}>", else: from

    "Email from #{display_from} - Subject: #{subject}\nContent: #{String.slice(content, 0, 500)}..."
  end

  defp format_context_item(%{
         document_type: "hubspot_contact",
         content: content,
         metadata: metadata
       }) do
    name = get_in(metadata, ["name"]) || "Unknown Contact"
    company = get_in(metadata, ["company"]) || ""
    company_text = if company != "", do: " (#{company})", else: ""
    "Contact: #{name}#{company_text}\nInfo: #{String.slice(content, 0, 500)}..."
  end

  defp format_context_item(%{document_type: "hubspot_note", content: content, metadata: metadata}) do
    contact_name = get_in(metadata, ["contact_name"]) || "Unknown Contact"
    note_type = get_in(metadata, ["note_type"]) || "Note"
    "#{note_type} for #{contact_name}:\n#{String.slice(content, 0, 500)}..."
  end

  defp format_context_item(item) do
    "Content: #{String.slice(item.content || "", 0, 500)}..."
  end
end

defmodule Agentleguide.Services.Ai.Clients.OllamaClient do
  @moduledoc """
  Ollama client implementation for AI services.
  """

  @behaviour Agentleguide.Services.Ai.AiClientBehaviour

  require Logger

  @ollama_chat_model "llama3.2:latest"
  @ollama_embedding_model "rjmalagon/gte-qwen2-1.5b-instruct-embed-f16"

  @impl true
  def generate_embeddings(text) do
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
         |> Finch.request(Agentleguide.Finch, receive_timeout: 60_000, request_timeout: 60_000) do
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

  @impl true
  def chat_completion(messages, opts \\ []) do
    user = Keyword.get(opts, :user)

    # Convert messages to Ollama format
    ollama_messages =
      Enum.map(messages, fn msg ->
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

  # Process Ollama response to detect and execute tool calls
  defp process_ollama_response_for_tools(content, user)
       when is_binary(content) and not is_nil(user) do
    case parse_tool_calls_from_text(content) do
      [] ->
        {:ok, content}

      tool_calls ->
        execute_tool_calls(tool_calls, user, content)
    end
  end

  defp process_ollama_response_for_tools(content, _user) do
    {:ok, content}
  end

  defp parse_tool_calls_from_text(content) do
    # Simple pattern matching for tool calls in text
    # Look for patterns like "TOOL_CALL: function_name" followed by "PARAMETERS: {...}"
    tool_pattern = ~r/TOOL_CALL:\s*(\w+)\s*\nPARAMETERS:\s*(\{[^}]*\})/

    Regex.scan(tool_pattern, content)
    |> Enum.map(fn [_match, function_name, params_json] ->
      case Jason.decode(params_json) do
        {:ok, params} -> {function_name, params}
        {:error, _} -> nil
      end
    end)
    |> Enum.filter(& &1)
  end

  defp execute_tool_calls(tool_calls, user, original_content) do
    results =
      Enum.map(tool_calls, fn {function_name, params} ->
        case Agentleguide.Services.Ai.AiTools.execute_tool_call(user, function_name, params) do
          {:ok, result} ->
            "Tool #{function_name} executed successfully: #{Jason.encode!(result)}"

          {:error, error} ->
            "Tool #{function_name} failed: #{error}"
        end
      end)

    if Enum.empty?(results) do
      {:ok, original_content}
    else
      combined_result = Enum.join(results, "\n\n")
      {:ok, combined_result}
    end
  end

  defp ollama_url do
    Application.get_env(:agentleguide, :ollama_url, "http://localhost:11434")
  end
end

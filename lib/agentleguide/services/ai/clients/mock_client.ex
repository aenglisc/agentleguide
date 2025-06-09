defmodule Agentleguide.Services.Ai.Clients.MockClient do
  @moduledoc """
  Mock client implementation for testing AI services.
  """

  @behaviour Agentleguide.Services.Ai.AiClientBehaviour

  @impl true
  def generate_embeddings(text) do
    # Return a mock embedding vector of the expected dimension
    case String.trim(text) do
      "" ->
        {:error, "Empty text provided"}

      "fail_embeddings" ->
        {:error, "Mock embedding failure"}

      _ ->
        # Generate deterministic mock embedding based on text content
        embedding =
          text
          |> String.codepoints()
          |> Enum.take(1536)
          |> Enum.with_index()
          |> Enum.map(fn {char, index} ->
            (String.to_charlist(char) |> hd() |> rem(100)) / 100.0 + index / 10000.0
          end)
          |> Enum.concat(List.duplicate(0.5, max(0, 1536 - String.length(text))))
          |> Enum.take(1536)

        {:ok, embedding}
    end
  end

  @impl true
  def chat_completion(messages, opts \\ []) do
    user_message =
      messages
      |> Enum.reverse()
      |> Enum.find(fn msg -> msg["role"] == "user" end)

    case user_message do
      nil ->
        {:error, "No user message found"}

      %{"content" => content} ->
        process_mock_response(content, opts)
    end
  end

  defp process_mock_response(content, opts) do
    user = Keyword.get(opts, :user)

    case String.downcase(String.trim(content)) do
      "fail_chat" ->
        {:error, "Mock chat failure"}

      "search contacts" when not is_nil(user) ->
        {:ok, "Mock tool response: Found 3 contacts"}

      "send email" when not is_nil(user) ->
        {:ok, "Mock tool response: Email sent successfully"}

      text ->
        if String.contains?(text, "tool") and not is_nil(user) do
          {:ok, "Mock response with tool capability: I can help you with that task."}
        else
          {:ok, "Mock AI response: I understand your request about '#{content}'"}
        end
    end
  end
end

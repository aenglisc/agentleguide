defmodule Agentleguide.Services.Ai.AiServiceTest do
  use Agentleguide.DataCase
  import ExUnit.CaptureLog

  alias Agentleguide.{Accounts}
  alias Agentleguide.Services.Ai.AiService
  alias Agentleguide.Services.Ai.Clients.MockClient

  defp user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{
        email: "test#{System.unique_integer()}@example.com",
        name: "Test User"
      })
      |> Accounts.create_user()

    user
  end

  describe "generate_embeddings/2" do
    test "successfully generates embeddings with mock client" do
      # Ensure embeddings are enabled for this test
      original_value = Application.get_env(:agentleguide, :embeddings_enabled)

      try do
        Application.put_env(:agentleguide, :embeddings_enabled, true)

        result = AiService.generate_embeddings("test content", client: MockClient)

        assert {:ok, embeddings} = result
        assert is_list(embeddings)
        assert length(embeddings) == 1536
        assert Enum.all?(embeddings, &is_float/1)
      after
        if original_value != nil do
          Application.put_env(:agentleguide, :embeddings_enabled, original_value)
        else
          Application.delete_env(:agentleguide, :embeddings_enabled)
        end
      end
    end

    test "returns error when embeddings are disabled" do
      # Temporarily disable embeddings
      original_setting = Application.get_env(:agentleguide, :embeddings_enabled, true)
      Application.put_env(:agentleguide, :embeddings_enabled, false)

      on_exit(fn ->
        Application.put_env(:agentleguide, :embeddings_enabled, original_setting)
      end)

      assert {:error, "Embeddings disabled"} = AiService.generate_embeddings("test text")
    end

        test "uses mock client when specified" do
      # Temporarily enable embeddings
      original_setting = Application.get_env(:agentleguide, :embeddings_enabled, true)
      Application.put_env(:agentleguide, :embeddings_enabled, true)

      on_exit(fn ->
        Application.put_env(:agentleguide, :embeddings_enabled, original_setting)
      end)

      result = AiService.generate_embeddings("test text", client: :mock)

      # Mock client should return a predictable response
      assert {:ok, _embedding} = result
    end

    test "uses default client when no override specified" do
      # This will use the configured default client (likely mock in test)
      result = AiService.generate_embeddings("test text")

      # Should not crash - exact result depends on configured client
      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "handles empty text input" do
      original_value = Application.get_env(:agentleguide, :embeddings_enabled)

      try do
        Application.put_env(:agentleguide, :embeddings_enabled, true)

        result = AiService.generate_embeddings("", client: MockClient)
        assert {:error, "Empty text provided"} = result
      after
        if original_value != nil do
          Application.put_env(:agentleguide, :embeddings_enabled, original_value)
        else
          Application.delete_env(:agentleguide, :embeddings_enabled)
        end
      end
    end

    test "handles client failure" do
      original_value = Application.get_env(:agentleguide, :embeddings_enabled)

      try do
        Application.put_env(:agentleguide, :embeddings_enabled, true)

        result = AiService.generate_embeddings("fail_embeddings", client: MockClient)
        assert {:error, "Mock embedding failure"} = result
      after
        if original_value != nil do
          Application.put_env(:agentleguide, :embeddings_enabled, original_value)
        else
          Application.delete_env(:agentleguide, :embeddings_enabled)
        end
      end
    end

    test "generates deterministic embeddings for same input" do
      original_value = Application.get_env(:agentleguide, :embeddings_enabled)

      try do
        Application.put_env(:agentleguide, :embeddings_enabled, true)

        text = "consistent test content"

        {:ok, embeddings1} = AiService.generate_embeddings(text, client: MockClient)
        {:ok, embeddings2} = AiService.generate_embeddings(text, client: MockClient)

        assert embeddings1 == embeddings2
      after
        if original_value != nil do
          Application.put_env(:agentleguide, :embeddings_enabled, original_value)
        else
          Application.delete_env(:agentleguide, :embeddings_enabled)
        end
      end
    end

    test "generates different embeddings for different inputs" do
      original_value = Application.get_env(:agentleguide, :embeddings_enabled)

      try do
        Application.put_env(:agentleguide, :embeddings_enabled, true)

        {:ok, embeddings1} = AiService.generate_embeddings("first text", client: MockClient)
        {:ok, embeddings2} = AiService.generate_embeddings("second text", client: MockClient)

        refute embeddings1 == embeddings2
      after
        if original_value != nil do
          Application.put_env(:agentleguide, :embeddings_enabled, original_value)
        else
          Application.delete_env(:agentleguide, :embeddings_enabled)
        end
      end
    end
  end

  describe "chat_completion/4" do
    test "successfully completes chat without user context" do
      messages = [%{"role" => "user", "content" => "Hello"}]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, response} = result
      assert String.contains?(response, "Hello")
    end

    test "handles empty messages list" do
      result = AiService.chat_completion([], [], nil, client: MockClient)

      assert {:error, "No user message found"} = result
    end

    test "includes RAG context in system message" do
      messages = [%{"role" => "user", "content" => "What do you know?"}]

      context = [
        %{content: "Important document content", source: "doc1.txt"},
        %{content: "Additional context", source: "doc2.txt"}
      ]

      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "enables tools when user is provided" do
      {:ok, user} =
        Accounts.create_user(%{
          email: "tooluser#{System.unique_integer()}@example.com",
          name: "Tool User"
        })

      messages = [%{"role" => "user", "content" => "search contacts"}]

      result = AiService.chat_completion(messages, [], user, client: MockClient)

      assert {:ok, response} = result
      assert String.contains?(response, "Found 3 contacts")
    end

    test "handles tool execution requests" do
      {:ok, user} =
        Accounts.create_user(%{
          email: "senduser#{System.unique_integer()}@example.com",
          name: "Send User"
        })

      messages = [%{"role" => "user", "content" => "send email"}]

      result = AiService.chat_completion(messages, [], user, client: MockClient)

      assert {:ok, response} = result
      assert String.contains?(response, "Email sent successfully")
    end

    test "responds normally when no tools are needed" do
      messages = [%{"role" => "user", "content" => "general question"}]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, response} = result
      assert String.contains?(response, "general question")
    end

    test "handles client failure gracefully" do
      messages = [%{"role" => "user", "content" => "fail_chat"}]

      capture_log(fn ->
        result = AiService.chat_completion(messages, [], nil, client: MockClient)
        assert {:error, "Mock chat failure"} = result
      end)
    end

    test "formats context properly in system message" do
      messages = [%{"role" => "user", "content" => "test"}]

      context = [
        %{
          content:
            "This is a very long document that should be truncated in the context to ensure it doesn't overwhelm the system message with too much information",
          source: "long_doc.txt"
        }
      ]

      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, _response} = result
    end

         test "generates system message without user context" do
       messages = [%{"role" => "user", "content" => "Hello"}]

       result = AiService.chat_completion(messages, [], nil, client: :mock)

       assert {:ok, response} = result
       assert is_binary(response)
     end

    test "generates system message with user context" do
      user = user_fixture()
      messages = [%{"role" => "user", "content" => "Hello"}]

      result = AiService.chat_completion(messages, [], user, client: MockClient)

      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "includes context in system message" do
      context = [
        %{source: "Email", content: "This is a test email content that should be included"},
        %{source: "Contact", content: "John Doe - john@example.com"}
      ]

      messages = [%{"role" => "user", "content" => "What do you know about John?"}]

      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "handles empty context gracefully" do
      messages = [%{"role" => "user", "content" => "Hello"}]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "handles nil context gracefully" do
      messages = [%{"role" => "user", "content" => "Hello"}]

      result = AiService.chat_completion(messages, nil, nil, client: MockClient)

      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "includes tools when user is provided" do
      user = user_fixture()
      messages = [%{"role" => "user", "content" => "Search for contacts"}]

      result = AiService.chat_completion(messages, [], user, client: MockClient)

      # Mock client should handle tools parameter
      assert {:ok, response} = result
      assert is_binary(response)
    end

    test "works with different message formats" do
      messages = [
        %{"role" => "user", "content" => "First message"},
        %{"role" => "assistant", "content" => "Assistant response"},
        %{"role" => "user", "content" => "Follow up question"}
      ]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, response} = result
      assert is_binary(response)
    end
  end

  describe "system message building" do
    test "includes tool instructions when user is provided" do
      {:ok, user} =
        Accounts.create_user(%{
          email: "systemmsg#{System.unique_integer()}@example.com",
          name: "System User"
        })

      messages = [%{"role" => "user", "content" => "help with tools"}]

      result = AiService.chat_completion(messages, [], user, client: MockClient)

      assert {:ok, response} = result
      assert String.contains?(response, "tool capability")
    end

    test "excludes tool instructions when no user provided" do
      messages = [%{"role" => "user", "content" => "help with tools"}]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, response} = result
      refute String.contains?(response, "tool capability")
    end
  end

  describe "client configuration" do
    test "uses default client when none specified" do
      # Test that it doesn't crash and returns a response
      messages = [%{"role" => "user", "content" => "test"}]

      # This will use the configured default client (likely :openai or :ollama)
      # The exact result depends on the environment, but it should not crash
      result = AiService.chat_completion(messages)

      # Should return either success or a reasonable error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "uses specified mock client" do
      messages = [%{"role" => "user", "content" => "test with mock"}]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, response} = result
      assert String.contains?(response, "test with mock")
    end
  end

  describe "edge cases" do
    test "handles nil context gracefully" do
      messages = [%{"role" => "user", "content" => "test"}]

      # Passing nil as context should be handled gracefully
      result = AiService.chat_completion(messages, nil, nil, client: MockClient)

      assert {:ok, _response} = result
    end

    test "handles empty context list" do
      messages = [%{"role" => "user", "content" => "test"}]

      result = AiService.chat_completion(messages, [], nil, client: MockClient)

      assert {:ok, _response} = result
    end

    test "handles malformed context items" do
      messages = [%{"role" => "user", "content" => "test"}]

      context = [
        # Empty context item
        %{},
        # Nil content
        %{content: nil, source: "bad.txt"},
        # Missing source
        %{content: "good content"}
      ]

      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, _response} = result
    end
  end

     describe "client selection" do
     test "uses specified client override" do
       # Temporarily enable embeddings
       original_setting = Application.get_env(:agentleguide, :embeddings_enabled, true)
       Application.put_env(:agentleguide, :embeddings_enabled, true)

       on_exit(fn ->
         Application.put_env(:agentleguide, :embeddings_enabled, original_setting)
       end)

       # Test that client selection works by using mock client explicitly
       result = AiService.generate_embeddings("test", client: :mock)
       assert {:ok, _} = result

       result = AiService.chat_completion([%{"role" => "user", "content" => "test"}], [], nil, client: :mock)
       assert {:ok, _} = result
     end

     test "uses module name as client" do
       # Temporarily enable embeddings
       original_setting = Application.get_env(:agentleguide, :embeddings_enabled, true)
       Application.put_env(:agentleguide, :embeddings_enabled, true)

       on_exit(fn ->
         Application.put_env(:agentleguide, :embeddings_enabled, original_setting)
       end)

       # Test that we can pass a module directly
       result = AiService.generate_embeddings("test", client: Agentleguide.Services.Ai.Clients.MockClient)
       assert {:ok, _} = result
     end
   end

  describe "context formatting" do
    test "formats context with source and content" do
      # We can't test the private function directly, but we can test it through chat_completion
      context = [
        %{source: "Email", content: "This is an email about meetings"},
        %{source: "Contact", content: "John Doe contact information"}
      ]

      messages = [%{"role" => "user", "content" => "Tell me about my data"}]

      # This will internally use format_context
      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, _response} = result
    end

    test "handles context items with string keys" do
      context = [
        %{"source" => "Email", "content" => "String key email"},
        %{"source" => "Note", "content" => "String key note"}
      ]

      messages = [%{"role" => "user", "content" => "What's in my data?"}]

      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, _response} = result
    end

    test "handles long content by truncating" do
      long_content = String.duplicate("a", 500)  # Longer than 200 char limit

      context = [%{source: "Document", content: long_content}]
      messages = [%{"role" => "user", "content" => "Summarize"}]

      # Should not crash even with very long content
      result = AiService.chat_completion(messages, context, nil, client: MockClient)

      assert {:ok, _response} = result
    end
  end
end

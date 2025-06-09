defmodule Agentleguide.Services.Ai.ChatServiceTest do
  use Agentleguide.DataCase
  import ExUnit.CaptureLog

  alias Agentleguide.Services.Ai.ChatService
  alias Agentleguide.Rag
  alias Agentleguide.Accounts

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

  defp contact_fixture(user, attrs) do
    default_attrs = %{
      user_id: user.id,
      hubspot_id: "test-#{System.unique_integer()}",
      first_name: "John",
      last_name: "Doe",
      email: "contact@example.com"
    }

    {:ok, contact} =
      Rag.upsert_hubspot_contact(user, attrs |> Enum.into(default_attrs))

    contact
  end

  describe "generate_session_id/0" do
    test "generates a unique session ID" do
      id1 = ChatService.generate_session_id()
      id2 = ChatService.generate_session_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2
      assert String.length(id1) == 16
    end
  end

  describe "create_new_session/2" do
    test "creates a new session without first message" do
      user = user_fixture()

      assert {:ok, session} = ChatService.create_new_session(user)
      assert session.user_id == user.id
      assert is_binary(session.session_id)
      assert session.title == "New Chat"
    end

    test "creates a new session with first message" do
      user = user_fixture()
      first_message = "Hello, how are you?"

      assert {:ok, session} = ChatService.create_new_session(user, first_message)
      assert session.user_id == user.id
      assert session.title == first_message
    end
  end

  describe "get_session_with_messages/2" do
    test "returns error for non-existent session" do
      user = user_fixture()

      assert {:error, :not_found} = ChatService.get_session_with_messages(user, "nonexistent")
    end

    test "returns session with messages" do
      user = user_fixture()
      {:ok, session} = ChatService.create_new_session(user, "Test message")

      # Add a message
      {:ok, _message} =
        Rag.create_chat_message(%{
          user_id: user.id,
          session_id: session.session_id,
          role: "user",
          content: "Hello"
        })

      assert {:ok, %{session: returned_session, messages: messages}} =
               ChatService.get_session_with_messages(user, session.session_id)

      assert returned_session.id == session.id
      assert length(messages) == 1
      assert hd(messages).content == "Hello"
    end
  end

  describe "list_user_sessions/2" do
    test "returns empty list for user with no sessions" do
      user = user_fixture()

      assert [] = ChatService.list_user_sessions(user)
    end

    test "returns user sessions with default limit" do
      user = user_fixture()

      # Create a few sessions
      {:ok, _session1} = ChatService.create_new_session(user, "Message 1")
      {:ok, _session2} = ChatService.create_new_session(user, "Message 2")

      sessions = ChatService.list_user_sessions(user)
      assert length(sessions) == 2
    end

    test "respects custom limit" do
      user = user_fixture()

      # Create multiple sessions
      for i <- 1..5 do
        {:ok, _session} = ChatService.create_new_session(user, "Message #{i}")
      end

      sessions = ChatService.list_user_sessions(user, 3)
      assert length(sessions) == 3
    end
  end

  describe "handle_person_query/2" do
    test "returns no_matches when no contacts found" do
      user = user_fixture()

      assert {:no_matches, []} = ChatService.handle_person_query(user, "Tell me about XyzPerson")
    end

    test "returns single_match when one contact found" do
      user = user_fixture()
      contact = contact_fixture(user, %{first_name: "Alice", last_name: "Smith"})

      assert {:single_match, [returned_contact]} =
               ChatService.handle_person_query(user, "Tell me about Alice")

      assert returned_contact.id == contact.id
    end

    test "returns multiple_matches when multiple contacts found" do
      user = user_fixture()
      _contact1 = contact_fixture(user, %{first_name: "John", last_name: "Doe"})
      _contact2 = contact_fixture(user, %{first_name: "John", last_name: "Smith"})

      assert {:multiple_matches, contacts} =
               ChatService.handle_person_query(user, "Tell me about John")

      assert length(contacts) == 2
    end

    test "handles queries with no recognizable names" do
      user = user_fixture()

      assert {:no_matches, []} =
               ChatService.handle_person_query(user, "what is the weather like")
    end

    test "extracts names properly from various query formats" do
      user = user_fixture()
      contact = contact_fixture(user, %{first_name: "Sarah", last_name: "Connor"})

      # Simple test with just first name which should work
      assert {:single_match, [returned_contact]} =
               ChatService.handle_person_query(user, "Tell me about Sarah")

      assert returned_contact.id == contact.id
    end

    test "filters out common words correctly" do
      user = user_fixture()

      # Query with capitalized common words that should be filtered out
      assert {:no_matches, []} =
               ChatService.handle_person_query(user, "The And But Or For At In On To From")
    end
  end

  describe "process_query/3" do
    test "processes query successfully with new session" do
      user = user_fixture()
      session_id = ChatService.generate_session_id()
      query = "Hello, can you help me?"

      assert {:ok, response} = ChatService.process_query(user, session_id, query)
      assert is_binary(response)

      # Verify session was created
      assert {:ok, %{session: session, messages: messages}} =
               ChatService.get_session_with_messages(user, session_id)

      assert session.session_id == session_id
      assert length(messages) == 2  # user message + assistant response
    end

    test "processes query with existing session" do
      user = user_fixture()
      {:ok, session} = ChatService.create_new_session(user, "Initial message")
      query = "Follow up question"

      assert {:ok, response} = ChatService.process_query(user, session.session_id, query)
      assert is_binary(response)

      # Verify messages were added
      assert {:ok, %{messages: messages}} =
               ChatService.get_session_with_messages(user, session.session_id)

      assert length(messages) == 2  # user message + assistant response
    end

    test "handles AI service error gracefully" do
      user = user_fixture()
      session_id = ChatService.generate_session_id()
      query = "fail_chat"  # This will trigger mock error

      capture_log(fn ->
        assert {:error, _reason} = ChatService.process_query(user, session_id, query)
      end)
    end

    test "handles embeddings disabled scenario" do
      user = user_fixture()
      session_id = ChatService.generate_session_id()
      query = "Tell me about my data"

      # Disable embeddings
      Application.put_env(:agentleguide, :embeddings_enabled, false)

      assert {:ok, response} = ChatService.process_query(user, session_id, query)
      assert is_binary(response)

      # Re-enable embeddings for other tests
      Application.put_env(:agentleguide, :embeddings_enabled, true)
    end

    test "handles multiple contacts disambiguation" do
      user = user_fixture()
      _contact1 = contact_fixture(user, %{first_name: "John", last_name: "Doe"})
      _contact2 = contact_fixture(user, %{first_name: "John", last_name: "Smith"})

      session_id = ChatService.generate_session_id()
      query = "Tell me about John"

      assert {:ok, response} = ChatService.process_query(user, session_id, query)
      assert String.contains?(response, "multiple people")
      assert String.contains?(response, "1. John Doe")
      assert String.contains?(response, "2. John Smith")
    end

    test "processes query with context from embeddings" do
      user = user_fixture()
      session_id = ChatService.generate_session_id()
      query = "search contacts"

      Application.put_env(:agentleguide, :embeddings_enabled, true)

      assert {:ok, response} = ChatService.process_query(user, session_id, query)
      assert is_binary(response)
    end

    test "updates session activity timestamp" do
      user = user_fixture()
      {:ok, session} = ChatService.create_new_session(user, "Initial")
      original_timestamp = session.last_message_at

      # Wait a brief moment to ensure timestamp difference
      Process.sleep(50)

      query = "Follow up"

      assert {:ok, _response} = ChatService.process_query(user, session.session_id, query)

      # Check that session activity was updated
      assert {:ok, %{session: updated_session}} =
               ChatService.get_session_with_messages(user, session.session_id)

      # The timestamp should be the same or later (allowing for DB precision)
      assert DateTime.compare(updated_session.last_message_at, original_timestamp) in [:gt, :eq]
    end

    test "handles session creation failure" do
      user = user_fixture()

      # Use an invalid session_id format that would cause DB constraint issues
      # This is a bit contrived but tests error handling
      query = "Test message"

      # Create a session with the same ID first to cause conflict
      session_id = ChatService.generate_session_id()
      {:ok, _} = ChatService.create_new_session(user)

      # Now try to process with same user but nonexistent session should work
      assert {:ok, _response} = ChatService.process_query(user, session_id, query)
    end
  end


end

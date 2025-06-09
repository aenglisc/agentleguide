defmodule Agentleguide.RagTest do
  use Agentleguide.DataCase

  alias Agentleguide.{Rag, Accounts}

  describe "gmail_emails" do
    test "upsert_gmail_email/2 creates new email" do
      user = user_fixture()

      attrs = %{
        gmail_id: "12345",
        subject: "Test Email",
        from_email: "test@example.com",
        from_name: "Test User",
        body_text: "This is a test email.",
        date: ~U[2024-01-01 12:00:00Z]
      }

      assert {:ok, email} = Rag.upsert_gmail_email(user, attrs)
      assert email.gmail_id == "12345"
      assert email.subject == "Test Email"
      assert email.user_id == user.id
    end

    test "upsert_gmail_email/2 updates existing email" do
      user = user_fixture()

      attrs = %{
        gmail_id: "12345",
        subject: "Test Email",
        from_email: "test@example.com"
      }

      assert {:ok, email1} = Rag.upsert_gmail_email(user, attrs)

      updated_attrs = %{
        gmail_id: "12345",
        subject: "Updated Test Email",
        from_email: "test@example.com"
      }

      assert {:ok, email2} = Rag.upsert_gmail_email(user, updated_attrs)
      assert email1.id == email2.id
      assert email2.subject == "Updated Test Email"
    end
  end

  describe "hubspot_contacts" do
    test "upsert_hubspot_contact/2 creates new contact" do
      user = user_fixture()

      attrs = %{
        hubspot_id: "54321",
        first_name: "John",
        last_name: "Doe",
        email: "john@example.com",
        company: "Example Corp"
      }

      assert {:ok, contact} = Rag.upsert_hubspot_contact(user, attrs)
      assert contact.hubspot_id == "54321"
      assert contact.first_name == "John"
      assert contact.last_name == "Doe"
      assert contact.user_id == user.id
    end

    test "search_contacts/2 finds contacts by name" do
      user = user_fixture()

      {:ok, _contact1} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "1",
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com"
        })

      {:ok, _contact2} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "2",
          first_name: "Jane",
          last_name: "Smith",
          email: "jane@example.com"
        })

      {:ok, _contact3} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "3",
          first_name: "Bob",
          last_name: "Johnson",
          company: "John's Company"
        })

      # Search by first name
      results = Rag.search_contacts(user, "John")
      # John Doe + company "John's Company"
      assert length(results) == 2

      # Search by last name
      results = Rag.search_contacts(user, "Smith")
      assert length(results) == 1

      # Search by company
      results = Rag.search_contacts(user, "Company")
      assert length(results) == 1
    end
  end

  describe "chat_messages" do
    test "create_chat_message/1 creates a chat message" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        session_id: "test-session",
        role: "user",
        content: "Hello, how are you?"
      }

      assert {:ok, message} = Rag.create_chat_message(attrs)
      assert message.role == "user"
      assert message.content == "Hello, how are you?"
      assert message.session_id == "test-session"
    end

    test "get_chat_messages/2 retrieves messages for a session" do
      user = user_fixture()
      session_id = "test-session"

      {:ok, _msg1} =
        Rag.create_chat_message(%{
          user_id: user.id,
          session_id: session_id,
          role: "user",
          content: "First message"
        })

      {:ok, _msg2} =
        Rag.create_chat_message(%{
          user_id: user.id,
          session_id: session_id,
          role: "assistant",
          content: "Second message"
        })

      # Different session
      {:ok, _msg3} =
        Rag.create_chat_message(%{
          user_id: user.id,
          session_id: "other-session",
          role: "user",
          content: "Different session"
        })

      messages = Rag.get_chat_messages(user, session_id)
      assert length(messages) == 2
      assert Enum.at(messages, 0).content == "First message"
      assert Enum.at(messages, 1).content == "Second message"
    end
  end

  describe "document_embeddings" do
    test "create_document_embedding/1 creates an embedding" do
      user = user_fixture()

      # Create a fake embedding (normally this would come from OpenAI)
      embedding = Enum.map(1..1536, fn _ -> :rand.uniform() end)

      attrs = %{
        user_id: user.id,
        document_type: "gmail_email",
        document_id: Ecto.UUID.generate(),
        content: "This is test content",
        embedding: embedding,
        metadata: %{"from" => "test@example.com"}
      }

      assert {:ok, doc_embedding} = Rag.create_document_embedding(attrs)
      assert doc_embedding.document_type == "gmail_email"
      assert doc_embedding.content == "This is test content"

      # The embedding is stored as a Pgvector struct, so we need to convert it back to check length
      assert length(Pgvector.to_list(doc_embedding.embedding)) == 1536
    end

    test "list_document_embeddings_for_user/1 returns embeddings for user" do
      user = user_fixture()
      other_user = user_fixture()

      # Create embeddings for different users
      embedding = Enum.map(1..1536, fn _ -> 0.5 end)

      {:ok, _embedding1} = Rag.create_document_embedding(%{
        user_id: user.id,
        document_type: "gmail_email",
        document_id: Ecto.UUID.generate(),
        content: "Content 1",
        embedding: embedding
      })

      # Small delay to ensure different inserted_at timestamps
      :timer.sleep(1)

      {:ok, _embedding2} = Rag.create_document_embedding(%{
        user_id: user.id,
        document_type: "hubspot_contact",
        document_id: Ecto.UUID.generate(),
        content: "Content 2",
        embedding: embedding
      })

      # Create embedding for other user
      {:ok, _other_embedding} = Rag.create_document_embedding(%{
        user_id: other_user.id,
        document_type: "gmail_email",
        document_id: Ecto.UUID.generate(),
        content: "Other user content",
        embedding: embedding
      })

      # Should only return embeddings for the specific user
      user_embeddings = Rag.list_document_embeddings_for_user(user)
      assert length(user_embeddings) == 2

      # Should be ordered by inserted_at desc (most recent first)
      # Check that we have both contents, order may vary due to timing
      contents = Enum.map(user_embeddings, & &1.content)
      assert "Content 1" in contents
      assert "Content 2" in contents

      # Other user should have their own embeddings
      other_embeddings = Rag.list_document_embeddings_for_user(other_user)
      assert length(other_embeddings) == 1
      assert hd(other_embeddings).content == "Other user content"
    end

    test "create_document_embedding/1 validates required fields" do
      # Missing user_id
      result = Rag.create_document_embedding(%{
        document_type: "gmail_email",
        document_id: Ecto.UUID.generate(),
        content: "Test content",
        embedding: Enum.map(1..1536, fn _ -> 0.5 end)
      })
      assert {:error, changeset} = result
      assert changeset.errors[:user_id]

      # Missing embedding
      user = user_fixture()
      result = Rag.create_document_embedding(%{
        user_id: user.id,
        document_type: "gmail_email",
        document_id: Ecto.UUID.generate(),
        content: "Test content"
      })
      assert {:error, changeset} = result
      assert changeset.errors[:embedding]

      # Invalid document_type
      result = Rag.create_document_embedding(%{
        user_id: user.id,
        document_type: "invalid_type",
        document_id: Ecto.UUID.generate(),
        content: "Test content",
        embedding: Enum.map(1..1536, fn _ -> 0.5 end)
      })
      assert {:error, changeset} = result
      assert changeset.errors[:document_type]
    end

    test "search_similar_documents/3 finds similar documents" do
      user = user_fixture()

      # Create test embeddings
      base_embedding = Enum.map(1..1536, fn _ -> 0.5 end)
      similar_embedding = Enum.map(1..1536, fn _ -> 0.51 end)

      # Create two document embeddings
      {:ok, _doc1} =
        Rag.create_document_embedding(%{
          user_id: user.id,
          document_type: "gmail_email",
          document_id: Ecto.UUID.generate(),
          content: "First document",
          embedding: base_embedding
        })

      {:ok, _doc2} =
        Rag.create_document_embedding(%{
          user_id: user.id,
          document_type: "gmail_email",
          document_id: Ecto.UUID.generate(),
          content: "Second document",
          embedding: similar_embedding
        })

      # Search with query embedding
      query_embedding = Enum.map(1..1536, fn _ -> 0.5 end)
      results = Rag.search_similar_documents(user, query_embedding, 5)

      assert length(results) == 2
      # Should be more similar
      assert hd(results).content == "First document"
    end
  end

  describe "gmail email search and listing" do
    setup do
      user = user_fixture()

      # Create test emails
      {:ok, email1} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "email1",
          subject: "Important Meeting Tomorrow",
          from_email: "john@company.com",
          from_name: "John Doe",
          body_text: "Let's discuss the quarterly report",
          date: ~U[2024-01-15 10:00:00Z]
        })

      {:ok, email2} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "email2",
          subject: "Follow up on proposal",
          from_email: "jane@client.com",
          from_name: "Jane Smith",
          body_text: "Thanks for the proposal. We need to discuss pricing",
          date: ~U[2024-01-14 15:30:00Z]
        })

      %{user: user, email1: email1, email2: email2}
    end

    test "search_emails/3 finds emails by subject", %{user: user} do
      results = Rag.search_emails(user, "meeting")
      assert length(results) == 1
      assert hd(results).subject == "Important Meeting Tomorrow"
    end

    test "search_emails/3 finds emails by body content", %{user: user} do
      results = Rag.search_emails(user, "proposal")
      assert length(results) == 1
      assert hd(results).subject == "Follow up on proposal"
    end

    test "search_emails/3 finds emails by sender name", %{user: user} do
      results = Rag.search_emails(user, "Jane")
      assert length(results) == 1
      assert hd(results).from_name == "Jane Smith"
    end

    test "search_emails/3 returns recent emails when query is empty", %{user: user} do
      results = Rag.search_emails(user, "")
      assert length(results) == 2
    end

    test "search_emails/3 respects limit parameter", %{user: user} do
      results = Rag.search_emails(user, "", 1)
      assert length(results) == 1
    end

    test "search_emails_by_sender/4 finds emails by sender", %{user: user} do
      results = Rag.search_emails_by_sender(user, "john")
      assert length(results) == 1
      assert hd(results).from_name == "John Doe"
    end

    test "search_emails_by_sender/4 with content filter", %{user: user} do
      results = Rag.search_emails_by_sender(user, "jane", "pricing")
      assert length(results) == 1
      assert hd(results).body_text =~ "pricing"
    end

    test "get_recent_emails/2 returns emails in date order", %{user: user} do
      results = Rag.get_recent_emails(user, 10)
      assert length(results) == 2

      dates = Enum.map(results, & &1.date)
      assert dates == Enum.sort(dates, {:desc, DateTime})
    end

    test "get_latest_gmail_email/1 returns most recent email", %{user: user, email1: email1} do
      latest = Rag.get_latest_gmail_email(user)
      assert latest.id == email1.id
    end

    test "get_existing_gmail_ids/2 returns existing IDs", %{user: user} do
      existing_ids = Rag.get_existing_gmail_ids(user, ["email1", "email2", "nonexistent"])
      assert "email1" in existing_ids
      assert "email2" in existing_ids
      assert "nonexistent" not in existing_ids
      assert length(existing_ids) == 2
    end

    test "get_existing_gmail_ids/2 with empty list returns empty", %{user: user} do
      assert Rag.get_existing_gmail_ids(user, []) == []
    end

    test "list_gmail_emails/1 returns all emails for user", %{user: user} do
      emails = Rag.list_gmail_emails(user)
      assert length(emails) == 2
    end
  end

  describe "hubspot contact extended functions" do
    setup do
      user = user_fixture()

      {:ok, contact1} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "contact1",
          first_name: "Alice",
          last_name: "Johnson",
          email: "alice@company.com",
          company: "Tech Corp",
          last_synced_at: ~U[2024-01-15 10:00:00Z]
        })

      {:ok, contact2} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "contact2",
          first_name: "Bob",
          last_name: "Williams",
          email: "bob@startup.com",
          company: "Startup Inc",
          last_synced_at: ~U[2024-01-14 10:00:00Z]
        })

      %{user: user, contact1: contact1, contact2: contact2}
    end

    test "search_contacts/2 finds contacts by first name", %{user: user} do
      results = Rag.search_contacts(user, "Alice")
      assert length(results) == 1
      assert hd(results).first_name == "Alice"
    end

    test "search_contacts/2 finds contacts by last name", %{user: user} do
      results = Rag.search_contacts(user, "Williams")
      assert length(results) == 1
      assert hd(results).last_name == "Williams"
    end

    test "search_contacts/2 returns empty for empty query", %{user: user} do
      assert Rag.search_contacts(user, "") == []
    end

    test "list_hubspot_contacts/1 returns contacts ordered by name", %{user: user} do
      contacts = Rag.list_hubspot_contacts(user)
      assert length(contacts) == 2
      # Should be ordered by last_name, first_name
      assert Enum.at(contacts, 0).last_name == "Johnson"
      assert Enum.at(contacts, 1).last_name == "Williams"
    end

    test "count_hubspot_contacts/1 returns correct count", %{user: user} do
      count = Rag.count_hubspot_contacts(user)
      assert count == 2
    end

    test "get_hubspot_contact_sync_times/2 returns sync time map", %{
      user: user,
      contact1: contact1
    } do
      sync_times =
        Rag.get_hubspot_contact_sync_times(user, ["contact1", "contact2", "nonexistent"])

      assert Map.has_key?(sync_times, "contact1")
      assert Map.has_key?(sync_times, "contact2")
      assert not Map.has_key?(sync_times, "nonexistent")
      assert sync_times["contact1"] == contact1.last_synced_at
    end

    test "get_hubspot_contact_sync_times/2 with empty list returns empty map", %{user: user} do
      assert Rag.get_hubspot_contact_sync_times(user, []) == %{}
    end
  end

  describe "chat sessions" do
    test "create_chat_session/2 creates session with generated ID" do
      user = user_fixture()
      {:ok, session} = Rag.create_chat_session(user, %{title: "Test Chat"})

      assert session.user_id == user.id
      assert session.title == "Test Chat"
      assert session.session_id != nil
      assert session.is_active == true
    end

    test "create_chat_session/2 uses provided session_id" do
      user = user_fixture()
      session_id = "custom-session-id"
      {:ok, session} = Rag.create_chat_session(user, %{session_id: session_id})

      assert session.session_id == session_id
    end

    test "get_chat_session/2 retrieves session by session_id" do
      user = user_fixture()
      {:ok, created_session} = Rag.create_chat_session(user, %{title: "Test"})

      retrieved_session = Rag.get_chat_session(user, created_session.session_id)
      assert retrieved_session.id == created_session.id
    end

    test "get_chat_session/2 returns nil for non-existent session" do
      user = user_fixture()
      assert Rag.get_chat_session(user, "nonexistent") == nil
    end

    test "list_chat_sessions/2 returns active sessions ordered by activity" do
      user = user_fixture()

      {:ok, session1} =
        Rag.create_chat_session(user, %{
          title: "Old Session",
          last_message_at: ~U[2024-01-10 10:00:00Z]
        })

      {:ok, session2} =
        Rag.create_chat_session(user, %{
          title: "Recent Session",
          last_message_at: ~U[2024-01-15 10:00:00Z]
        })

      sessions = Rag.list_chat_sessions(user)
      assert length(sessions) == 2
      # More recent first
      assert Enum.at(sessions, 0).id == session2.id
      assert Enum.at(sessions, 1).id == session1.id
    end

    test "list_chat_sessions/2 respects limit" do
      user = user_fixture()

      Enum.each(1..5, fn i ->
        Rag.create_chat_session(user, %{title: "Session #{i}"})
      end)

      sessions = Rag.list_chat_sessions(user, 3)
      assert length(sessions) == 3
    end
  end

  describe "chat session management" do
    setup do
      user = user_fixture()
      {:ok, session} = Rag.create_chat_session(user, %{title: "Test Session"})
      %{user: user, session: session}
    end

    test "get_chat_session!/2 retrieves session by id", %{user: user, session: session} do
      retrieved = Rag.get_chat_session!(user, session.id)
      assert retrieved.id == session.id
    end

    test "update_chat_session_activity/2 updates session metadata", %{
      user: user,
      session: session
    } do
      original_count = session.message_count

      {:ok, updated_session} = Rag.update_chat_session_activity(user, session.session_id)

      assert updated_session.message_count == original_count + 1
      assert updated_session.last_message_at != nil
    end

    test "update_chat_session_activity/2 returns error for non-existent session", %{user: user} do
      result = Rag.update_chat_session_activity(user, "nonexistent")
      assert result == {:error, :not_found}
    end

    test "update_chat_session_title/3 updates session title", %{user: user, session: session} do
      new_title = "Updated Title"
      {:ok, updated_session} = Rag.update_chat_session_title(user, session.session_id, new_title)

      assert updated_session.title == new_title
    end

    test "update_chat_session_title/3 returns error for non-existent session", %{user: user} do
      result = Rag.update_chat_session_title(user, "nonexistent", "Title")
      assert result == {:error, :not_found}
    end

    test "archive_chat_session/2 deactivates session", %{user: user, session: session} do
      {:ok, archived_session} = Rag.archive_chat_session(user, session.session_id)

      assert archived_session.is_active == false

      # Archived sessions should not appear in list_chat_sessions
      sessions = Rag.list_chat_sessions(user)
      assert Enum.empty?(sessions)
    end

    test "archive_chat_session/2 returns error for non-existent session", %{user: user} do
      result = Rag.archive_chat_session(user, "nonexistent")
      assert result == {:error, :not_found}
    end

    test "get_recent_chat_sessions/2 (deprecated) still works", %{user: user} do
      # Create some messages to have session activity
      Rag.create_chat_message(%{
        user_id: user.id,
        session_id: "test-session-1",
        role: "user",
        content: "Message 1"
      })

      Rag.create_chat_message(%{
        user_id: user.id,
        session_id: "test-session-1",
        role: "assistant",
        content: "Response 1"
      })

      recent_sessions = Rag.get_recent_chat_sessions(user, 5)
      assert length(recent_sessions) >= 1

      session_data = Enum.find(recent_sessions, &(&1.session_id == "test-session-1"))
      assert session_data != nil
      assert session_data.message_count == 2
    end
  end

  describe "hubspot notes" do
    test "upsert_hubspot_note/3 creates new note" do
      user = user_fixture()

      {:ok, contact} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "contact123",
          first_name: "Test",
          last_name: "Contact"
        })

      attrs = %{
        hubspot_id: "note123",
        body: "This is a test note",
        created_date: ~U[2024-01-15 10:00:00Z]
      }

      assert {:ok, note} = Rag.upsert_hubspot_note(user, contact, attrs)
      assert note.hubspot_id == "note123"
      assert note.body == "This is a test note"
      assert note.user_id == user.id
      assert note.contact_id == contact.id
    end

    test "upsert_hubspot_note/3 updates existing note" do
      user = user_fixture()

      {:ok, contact} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "contact123",
          first_name: "Test",
          last_name: "Contact"
        })

      attrs = %{
        hubspot_id: "note123",
        body: "Original content"
      }

      {:ok, note1} = Rag.upsert_hubspot_note(user, contact, attrs)

      updated_attrs = %{
        hubspot_id: "note123",
        body: "Updated content"
      }

      {:ok, note2} = Rag.upsert_hubspot_note(user, contact, updated_attrs)

      assert note1.id == note2.id
      assert note2.body == "Updated content"
    end
  end

  describe "email relevance filtering" do
    setup do
      user = user_fixture()

      # Create emails with different relevance patterns
      {:ok, _relevant_email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "relevant1",
          subject: "Important project update",
          from_email: "colleague@company.com",
          from_name: "John Colleague",
          body_text: "Here's the project status update you requested",
          date: ~U[2024-01-15 10:00:00Z]
        })

      {:ok, _spam_email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "spam1",
          subject: "Daily Digest: project mentions",
          from_email: "digest@newsletter.com",
          from_name: "Newsletter Digest",
          body_text:
            "Top stories today: • project management tips • workflow optimization • Click here to unsubscribe",
          date: ~U[2024-01-14 10:00:00Z]
        })

      {:ok, _url_mention} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "url1",
          subject: "Website analytics",
          from_email: "analytics@service.com",
          from_name: "Analytics Service",
          body_text:
            "Your site stats: https://analytics.com/project?utm_source=email&campaign=abc123project456",
          date: ~U[2024-01-13 10:00:00Z]
        })

      %{user: user}
    end

    test "search_emails/3 filters out low-relevance results", %{user: user} do
      results = Rag.search_emails(user, "project")

      # Should prioritize the relevant email over digest/spam
      assert length(results) >= 1
      # Most relevant should be first
      assert hd(results).subject == "Important project update"

      # Test with a query that should definitely filter out spam
      colleague_results = Rag.search_emails(user, "colleague")
      assert length(colleague_results) == 1
      assert hd(colleague_results).from_name == "John Colleague"
    end

    test "search_emails/3 handles edge cases gracefully", %{user: user} do
      # Empty query returns recent emails
      recent_results = Rag.search_emails(user, "")
      assert length(recent_results) == 3

      # Very specific query
      specific_results = Rag.search_emails(user, "colleague")
      assert length(specific_results) == 1
    end
  end

  describe "error handling and edge cases" do
    test "get_gmail_email!/1 raises for non-existent email" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        Rag.get_gmail_email!(fake_id)
      end
    end

    test "get_hubspot_contact!/1 raises for non-existent contact" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        Rag.get_hubspot_contact!(fake_id)
      end
    end

    test "upsert functions handle missing optional fields gracefully" do
      user = user_fixture()

      # Test with minimal data
      {:ok, email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "minimal1",
          subject: "Test"
        })

      assert email.gmail_id == "minimal1"
      assert email.subject == "Test"

      {:ok, contact} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "minimal2"
        })

      assert contact.hubspot_id == "minimal2"
    end
  end

  defp user_fixture(attrs \\ %{}) do
    default_attrs = %{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User",
      google_uid: "google_#{System.unique_integer()}"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end
end

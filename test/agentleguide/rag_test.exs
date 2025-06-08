defmodule Agentleguide.RagTest do
  use Agentleguide.DataCase, async: true

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

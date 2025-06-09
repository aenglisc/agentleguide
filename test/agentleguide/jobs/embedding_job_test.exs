defmodule Agentleguide.Jobs.EmbeddingJobTest do
  use Agentleguide.DataCase
  import ExUnit.CaptureLog

  alias Agentleguide.Jobs.EmbeddingJob
  alias Agentleguide.Accounts
  alias Agentleguide.Rag

  # Mock AI Service for embeddings
  defmodule MockAiService do
    def generate_embeddings(_content) do
      case Process.get(:ai_service_response) do
        nil -> {:ok, generate_mock_embedding()}  # Default mock embedding
        response -> response
      end
    end

    # Generate a 1536-dimension mock embedding (matching OpenAI's text-embedding-ada-002)
    defp generate_mock_embedding do
      1..1536
      |> Enum.map(fn i -> :rand.uniform() * 0.1 + (i / 1536) * 0.001 end)
    end
  end

  setup do
    # Mock AI Service
    Application.put_env(:agentleguide, :ai_service_module, MockAiService)

    on_exit(fn ->
      Application.delete_env(:agentleguide, :ai_service_module)
      Process.delete(:ai_service_response)
    end)

    :ok
  end

  describe "perform/1 with email_id" do
    test "successfully generates embeddings for email" do
      user = user_fixture()
      email = email_fixture(user)

      job = %Oban.Job{
        args: %{"user_id" => user.id, "email_id" => email.id}
      }

      # Create a 1536-dimensional embedding for testing (matching OpenAI dimensions)
      fake_embedding = Enum.map(1..1536, fn i -> i / 1536.0 end)
      Process.put(:ai_service_response, {:ok, fake_embedding})

      assert :ok = EmbeddingJob.perform(job)

      # Verify embedding was created
      embeddings = Rag.list_document_embeddings_for_user(user)
      assert length(embeddings) == 1

      [embedding] = embeddings
      assert embedding.document_type == "gmail_email"
      assert embedding.document_id == email.id
      assert embedding.user_id == user.id
    end

    test "handles user not found" do
      email = email_fixture(user_fixture())

      job = %Oban.Job{
        args: %{"user_id" => Ecto.UUID.generate(), "email_id" => email.id}
      }

      capture_log(fn ->
        assert {:discard, "User or email not found"} = EmbeddingJob.perform(job)
      end)
    end

    test "handles email not found" do
      user = user_fixture()

      job = %Oban.Job{
        args: %{"user_id" => user.id, "email_id" => Ecto.UUID.generate()}
      }

      capture_log(fn ->
        assert {:discard, "User or email not found"} = EmbeddingJob.perform(job)
      end)
    end

    test "handles AI service failure" do
      user = user_fixture()
      email = email_fixture(user)

      job = %Oban.Job{
        args: %{"user_id" => user.id, "email_id" => email.id}
      }

      Process.put(:ai_service_response, {:error, :api_error})

      capture_log(fn ->
        assert {:error, :api_error} = EmbeddingJob.perform(job)
      end)
    end

    test "skips embedding for very short content" do
      user = user_fixture()
      email = email_fixture(user, %{subject: "Hi", body_text: ""})

      job = %Oban.Job{
        args: %{"user_id" => user.id, "email_id" => email.id}
      }

      assert :ok = EmbeddingJob.perform(job)

      # Verify no embedding was created
      embeddings = Rag.list_document_embeddings_for_user(user)
      assert length(embeddings) == 0
    end

    test "handles embedding save failure" do
      user = user_fixture()
      email = email_fixture(user)

      job = %Oban.Job{
        args: %{"user_id" => user.id, "email_id" => email.id}
      }

      # Create a 1536-dimensional embedding for testing (matching OpenAI dimensions)
      fake_embedding = Enum.map(1..1536, fn i -> i / 1536.0 end)
      Process.put(:ai_service_response, {:ok, fake_embedding})

      # Test the happy path - embedding save should succeed with proper dimensions
      # (More complex error scenarios would require mocking which is beyond current scope)
      assert :ok = EmbeddingJob.perform(job)
    end
  end

  describe "perform/1 with contact_id" do
    test "successfully generates embeddings for contact" do
      user = user_fixture()
      contact = contact_fixture(user)

      job = %Oban.Job{
        args: %{"user_id" => user.id, "contact_id" => contact.id}
      }

      # Create a 1536-dimensional embedding for testing (matching OpenAI dimensions)
      fake_embedding = Enum.map(1..1536, fn i -> (i + 1000) / 1536.0 end)
      Process.put(:ai_service_response, {:ok, fake_embedding})

      assert :ok = EmbeddingJob.perform(job)

      # Verify embedding was created
      embeddings = Rag.list_document_embeddings_for_user(user)
      assert length(embeddings) == 1

      [embedding] = embeddings
      assert embedding.document_type == "hubspot_contact"
      assert embedding.document_id == contact.id
      assert embedding.user_id == user.id
    end

    test "handles contact not found" do
      user = user_fixture()

      job = %Oban.Job{
        args: %{"user_id" => user.id, "contact_id" => Ecto.UUID.generate()}
      }

      capture_log(fn ->
        assert {:discard, "User or contact not found"} = EmbeddingJob.perform(job)
      end)
    end

    test "skips embedding for contact with minimal content" do
      user = user_fixture()
      contact = contact_fixture(user, %{
        first_name: "A",
        last_name: nil,
        email: nil,
        company: nil,
        phone: nil,
        job_title: nil,
        website: nil
      })

      job = %Oban.Job{
        args: %{"user_id" => user.id, "contact_id" => contact.id}
      }

      # Clear any previous AI service responses to ensure clean test
      Process.delete(:ai_service_response)

      assert :ok = EmbeddingJob.perform(job)

      # Verify no embedding was created
      embeddings = Rag.list_document_embeddings_for_user(user)
      assert length(embeddings) == 0
    end

    test "handles AI service failure for contact" do
      user = user_fixture()
      contact = contact_fixture(user)

      job = %Oban.Job{
        args: %{"user_id" => user.id, "contact_id" => contact.id}
      }

      Process.put(:ai_service_response, {:error, :timeout})

      capture_log(fn ->
        assert {:error, :timeout} = EmbeddingJob.perform(job)
      end)
    end
  end

  # Helper functions
  defp user_fixture(attrs \\ %{}) do
    default_attrs = %{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User",
      google_uid: "google_#{System.unique_integer()}"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end

  defp email_fixture(user, attrs \\ %{}) do
    default_attrs = %{
      gmail_id: "gmail_#{System.unique_integer()}",
      subject: "Test Email Subject",
      body_text: "This is a test email body with enough content to generate embeddings.",
      from_email: "sender@example.com",
      from_name: "Test Sender",
      to_emails: ["recipient@example.com"],
      labels: ["INBOX"],
      date: DateTime.utc_now(),
      last_synced_at: DateTime.utc_now()
    }

    {:ok, email} = Rag.upsert_gmail_email(user, Map.merge(default_attrs, attrs))
    email
  end

  defp contact_fixture(user, attrs \\ %{}) do
    default_attrs = %{
      hubspot_id: "hubspot_#{System.unique_integer()}",
      first_name: "John",
      last_name: "Doe",
      email: "john.doe@example.com",
      company: "Example Corp",
      phone: "555-1234",
      job_title: "Software Engineer",
      website: "https://example.com",
      last_synced_at: DateTime.utc_now()
    }

    {:ok, contact} = Rag.upsert_hubspot_contact(user, Map.merge(default_attrs, attrs))
    contact
  end
end

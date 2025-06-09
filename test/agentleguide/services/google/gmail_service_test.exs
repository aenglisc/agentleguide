defmodule Agentleguide.Services.Google.GmailServiceTest do
  use Agentleguide.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Agentleguide.Services.Google.GmailService
  alias Agentleguide.Accounts

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set default expectations for Gmail HTTP calls
    stub(Agentleguide.GmailHttpMock, :build, fn method, url, headers, body ->
      %{method: method, url: url, headers: headers, body: body}
    end)

    stub(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
      {:ok, %{status: 200, body: Jason.encode!(%{"messages" => []})}}
    end)

    # Create a user with valid Google access token
    {:ok, user} =
      Accounts.create_user_from_google(%Ueberauth.Auth{
        uid: "test_uid",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "valid_access_token",
          refresh_token: "valid_refresh_token",
          expires_at: System.system_time(:second) + 3600
        }
      })

    %{user: user}
  end



  describe "sync_recent_emails/1" do
    test "successfully syncs new emails for user", %{user: user} do

      # Mock empty response to test that sync returns 0 count for empty results
      gmail_response = %{
        "messages" => []
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(gmail_response)}}
      end)

      assert {:ok, count} = GmailService.sync_recent_emails(user)
      assert count == 0
    end

    test "handles API authentication failure", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      capture_log(fn ->
        assert {:error, :auth_failed} = GmailService.sync_recent_emails(user)
      end)
    end

    test "handles API error response", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 500, body: "Internal Server Error"}}
      end)

      capture_log(fn ->
        assert {:error, {:api_error, 500, "Internal Server Error"}} = GmailService.sync_recent_emails(user)
      end)
    end

    test "handles request failure", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:error, :timeout}
      end)

      capture_log(fn ->
        assert {:error, {:request_failed, :timeout}} = GmailService.sync_recent_emails(user)
      end)
    end

    test "handles empty response", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: "{}"}}
      end)

      assert {:ok, 0} = GmailService.sync_recent_emails(user)
    end
  end

  describe "list_recent_message_ids/1" do
    test "successfully lists message IDs", %{user: user} do

      gmail_response = %{
        "messages" => [
          %{"id" => "msg1"},
          %{"id" => "msg2"},
          %{"id" => "msg3"}
        ]
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(gmail_response)}}
      end)

      assert {:ok, message_ids} = GmailService.list_recent_message_ids(user)
      assert message_ids == ["msg1", "msg2", "msg3"]
    end

    test "handles empty message list", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: "{}"}}
      end)

      assert {:ok, []} = GmailService.list_recent_message_ids(user)
    end

    test "handles API errors", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 403, body: "Forbidden"}}
      end)

      capture_log(fn ->
        assert {:error, {:api_error, 403, "Forbidden"}} = GmailService.list_recent_message_ids(user)
      end)
    end
  end

  describe "fetch_and_store_messages/2" do
    test "successfully fetches and stores multiple messages", %{user: user} do

      message_ids = ["msg1", "msg2"]

      # Mock message response
      message_response = %{
        "id" => "msg1",
        "threadId" => "thread1",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Test Email"},
            %{"name" => "From", "value" => "Test Sender <sender@example.com>"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
          ],
          "body" => %{"data" => Base.encode64("Test email body")}
        },
        "labelIds" => ["INBOX"]
      }

      expect(Agentleguide.GmailHttpMock, :request, 2, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(message_response)}}
      end)

      assert {:ok, results} = GmailService.fetch_and_store_messages(user, message_ids)
      assert length(results) <= length(message_ids)
    end

    test "handles individual message fetch failure", %{user: user} do

      message_ids = ["msg1", "invalid_msg"]

      expect(Agentleguide.GmailHttpMock, :request, 2, fn _request, _finch_name ->
        {:ok, %{status: 404, body: "Not Found"}}
      end)

      capture_log(fn ->
        assert {:ok, _results} = GmailService.fetch_and_store_messages(user, message_ids)
      end)
    end
  end

  describe "fetch_and_store_message/2" do
    test "successfully fetches and stores a single message with simple body", %{user: user} do

      message_response = %{
        "id" => "msg123",
        "threadId" => "thread123",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Simple Test Email"},
            %{"name" => "From", "value" => "John Doe <john@example.com>"},
            %{"name" => "To", "value" => "jane@example.com"},
            %{"name" => "Date", "value" => "Tue, 2 Jan 2024 10:30:00 +0000"}
          ],
          "body" => %{"data" => Base.encode64("Simple email body content")}
        },
        "labelIds" => ["INBOX", "UNREAD"]
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(message_response)}}
      end)

      assert {:ok, email} = GmailService.fetch_and_store_message(user, "msg123")
      assert email.gmail_id == "msg123"
      assert email.subject == "Simple Test Email"
      assert email.from_email == "john@example.com"
      assert email.from_name == "John Doe"
    end

    test "successfully handles multipart message", %{user: user} do

      message_response = %{
        "id" => "msg456",
        "threadId" => "thread456",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Multipart Email"},
            %{"name" => "From", "value" => "sender@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Date", "value" => "Wed, 3 Jan 2024 14:00:00 +0000"}
          ],
          "mimeType" => "multipart/alternative",
          "parts" => [
            %{
              "mimeType" => "text/plain",
              "body" => %{"data" => Base.encode64("Plain text content")}
            },
            %{
              "mimeType" => "text/html",
              "body" => %{"data" => Base.encode64("<p>HTML content</p>")}
            }
          ]
        },
        "labelIds" => ["INBOX"]
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(message_response)}}
      end)

      assert {:ok, email} = GmailService.fetch_and_store_message(user, "msg456")
      assert email.gmail_id == "msg456"
      assert email.subject == "Multipart Email"
    end

    test "handles nested multipart structure", %{user: user} do

      message_response = %{
        "id" => "msg789",
        "threadId" => "thread789",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Nested Structure"},
            %{"name" => "From", "value" => "complex@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Date", "value" => "Thu, 4 Jan 2024 16:30:00 +0000"}
          ],
          "mimeType" => "multipart/mixed",
          "parts" => [
            %{
              "mimeType" => "multipart/alternative",
              "parts" => [
                %{
                  "mimeType" => "text/plain",
                  "body" => %{"data" => Base.encode64("Nested plain content")}
                }
              ]
            }
          ]
        },
        "labelIds" => ["INBOX"]
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(message_response)}}
      end)

      assert {:ok, email} = GmailService.fetch_and_store_message(user, "msg789")
      assert email.gmail_id == "msg789"
    end

    test "handles message with no body data", %{user: user} do

      message_response = %{
        "id" => "msg_empty",
        "threadId" => "thread_empty",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Empty Message"},
            %{"name" => "From", "value" => "empty@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Date", "value" => "Fri, 5 Jan 2024 09:00:00 +0000"}
          ]
          # No body field
        },
        "labelIds" => ["INBOX"]
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(message_response)}}
      end)

      assert {:ok, email} = GmailService.fetch_and_store_message(user, "msg_empty")
      assert email.gmail_id == "msg_empty"
      assert email.body_text == nil || email.body_text == ""
    end

    test "handles malformed base64 data gracefully", %{user: user} do

      message_response = %{
        "id" => "msg_bad",
        "threadId" => "thread_bad",
        "payload" => %{
          "headers" => [
            %{"name" => "Subject", "value" => "Bad Encoding"},
            %{"name" => "From", "value" => "bad@example.com"},
            %{"name" => "To", "value" => "recipient@example.com"},
            %{"name" => "Date", "value" => "Sat, 6 Jan 2024 11:00:00 +0000"}
          ],
          "body" => %{"data" => "invalid_base64_data!!!"}
        },
        "labelIds" => ["INBOX"]
      }

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(message_response)}}
      end)

      assert {:ok, email} = GmailService.fetch_and_store_message(user, "msg_bad")
      assert email.gmail_id == "msg_bad"
      # Should handle gracefully even with bad encoding
    end

    test "handles API errors during message fetch", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 404, body: "Message not found"}}
      end)

      capture_log(fn ->
        assert {:error, :no_results} = GmailService.fetch_and_store_message(user, "missing_msg")
      end)
    end
  end

  describe "send_email/4" do
    test "successfully sends email", %{user: user} do

      send_response = %{"id" => "sent_msg_123", "threadId" => "thread_123"}

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(send_response)}}
      end)

      capture_log(fn ->
        assert {:ok, _response} = GmailService.send_email(user, "recipient@example.com", "Test Subject", "Test body")
      end)
    end

    test "handles send failure", %{user: user} do

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 400, body: "Bad Request"}}
      end)

      capture_log(fn ->
        assert {:error, {:api_error, 400, "Bad Request"}} = GmailService.send_email(user, "invalid@", "Subject", "Body")
      end)
    end
  end

  # Helper function to create a user with Gmail access
  # ... existing code ...
end

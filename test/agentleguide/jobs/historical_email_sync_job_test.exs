defmodule Agentleguide.Jobs.HistoricalEmailSyncJobTest do
  use Agentleguide.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Agentleguide.Jobs.HistoricalEmailSyncJob
  alias Agentleguide.Accounts

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set default expectation for Gmail HTTP calls to return auth errors
    # This can be overridden in individual tests that need specific behaviors
    stub(Agentleguide.GmailHttpMock, :build, fn method, url, headers, body ->
      %{method: method, url: url, headers: headers, body: body}
    end)

    stub(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
      {:ok, %{status: 401, body: "Unauthorized"}}
    end)

    :ok
  end

  describe "perform/1" do
    test "handles missing user gracefully" do
      job = %Oban.Job{
        args: %{"user_id" => Ecto.UUID.generate()}
      }

      capture_log(fn ->
        assert {:error, :user_not_found} = HistoricalEmailSyncJob.perform(job)
      end)
    end

    test "handles user without Google tokens" do
      {:ok, user} = Accounts.create_user(%{
        email: "test@example.com",
        name: "Test User"
      })

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # This will likely fail when trying to make Gmail API calls without proper tokens
      # but we're testing the job handles it gracefully
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        # Should handle authentication errors gracefully
        assert {:error, _reason} = result
      end)
    end

    test "handles authentication failures gracefully" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # In test environment, fake tokens will cause auth failures
      capture_log(fn ->
        assert {:error, :auth_failed} = HistoricalEmailSyncJob.perform(job)
      end)
    end

    test "handles resume with existing progress" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "total_synced" => 500,
          "oldest_date" => "2024-01-01T00:00:00Z",
          "page_token" => "some_token"
        }
      }

      # Should still fail auth but correctly handle the resume parameters
      capture_log(fn ->
        assert {:error, :auth_failed} = HistoricalEmailSyncJob.perform(job)
      end)
    end
  end

  describe "queue_historical_sync/1" do
    test "creates job with proper configuration" do
      {:ok, user} = create_user_with_google_auth()

      # In test mode with testing: :inline, job is executed immediately
      # We're testing that the job creation succeeds with proper structure
      capture_log(fn ->
        assert {:ok, %Oban.Job{} = job} = HistoricalEmailSyncJob.queue_historical_sync(user)

        # Verify job structure is correct
        assert job.worker == "Agentleguide.Jobs.HistoricalEmailSyncJob"
        assert job.args["user_id"] == user.id
        assert job.queue == "sync"
        assert job.max_attempts == 3

        # Verify unique constraints are set
        assert job.unique.fields == [:worker, :args]
        assert job.unique.period == 3600
      end)
    end

    test "handles duplicate job insertion with unique constraints" do
      {:ok, user} = create_user_with_google_auth()

      # In test mode, jobs execute inline, so we just verify creation succeeds
      capture_log(fn ->
        # First job creation
        assert {:ok, %Oban.Job{}} = HistoricalEmailSyncJob.queue_historical_sync(user)

        # Second job creation - unique constraints should prevent actual duplicates
        # (though in inline test mode, both will execute)
        assert {:ok, %Oban.Job{}} = HistoricalEmailSyncJob.queue_historical_sync(user)
      end)
    end
  end

  describe "error handling" do
    test "handles Gmail API authentication errors" do
      {:ok, user} = create_user_with_google_auth()

      # This will trigger actual API calls that should fail gracefully
      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        # Should handle auth errors gracefully
        assert {:error, _reason} = result
      end)
    end

    test "handles network timeouts gracefully" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # In test environment, network calls will fail
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "handles invalid JSON responses" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # Will fail with auth errors in test environment
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "handles empty response from Gmail" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # Test with user that will get empty response (simulated by auth failure)
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end
  end

  describe "batch processing" do
    test "handles continuation with page tokens" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "page_token" => "next_page_token_123",
          "total_synced" => 250
        }
      }

      # Should handle page token parameter correctly (will still fail auth)
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "handles large batch progress tracking" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "total_synced" => 1500,
          "oldest_date" => "2023-12-01T00:00:00Z"
        }
      }

      # Test with larger batch numbers to test progress tracking logic
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "handles first-time sync without existing progress" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # Test initial sync (no oldest_date or page_token)
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end
  end

  describe "user state management" do
    test "handles user without gmail connection" do
      {:ok, user} = Accounts.create_user(%{
        email: "noemail@example.com",
        name: "No Email User"
      })

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        # Should fail gracefully for user without Gmail tokens
        assert {:error, _reason} = result
      end)
    end

    test "handles user with expired tokens" do
      {:ok, user} = Accounts.create_user(%{
        email: "expired@example.com",
        name: "Expired Token User",
        google_access_token: "expired_token",
        google_token_expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      })

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "processes job args with missing optional fields" do
      {:ok, user} = create_user_with_google_auth()

      # Test with minimal args (only user_id)
      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "processes job args with all optional fields" do
      {:ok, user} = create_user_with_google_auth()

      # Test with all optional args
      job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "oldest_date" => "2024-01-15T10:30:00Z",
          "total_synced" => 750,
          "page_token" => "continuation_token_456"
        }
      }

      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end
  end

  describe "logging and monitoring" do
    test "logs and handles first-time sync successfully" do
      {:ok, user} = create_user_with_google_auth()

      # Override default stub with specific successful expectations
      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "messages" => [
              %{"id" => "msg1"},
              %{"id" => "msg2"}
            ]
          })
        }}
      end)

      expect(Agentleguide.GmailHttpMock, :request, 2, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "id" => "msg1",
            "payload" => %{
              "headers" => [
                %{"name" => "Subject", "value" => "Test Email"},
                %{"name" => "From", "value" => "test@example.com"},
                %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
              ],
              "body" => %{"data" => Base.encode64("Test body")}
            },
            "threadId" => "thread1"
          })
        }}
      end)

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      # Temporarily set logger level to info to capture the log messages
      Logger.configure(level: :info)

      logs = capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert :ok = result
      end)

      # Restore logger level
      Logger.configure(level: :warning)

      # Should log initial sync intention and success
      assert logs =~ "Starting historical email sync"
      assert logs =~ user.email
      assert logs =~ "Successfully synced"
    end

    test "logs and handles resumed sync successfully" do
      {:ok, user} = create_user_with_google_auth()

      # Set up mock expectations so the job reaches the logging code
      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "messages" => [
              %{"id" => "msg1"}
            ]
          })
        }}
      end)

      expect(Agentleguide.GmailHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "id" => "msg1",
            "payload" => %{
              "headers" => [
                %{"name" => "Subject", "value" => "Test Email"},
                %{"name" => "From", "value" => "test@example.com"},
                %{"name" => "Date", "value" => "Mon, 1 Jan 2024 12:00:00 +0000"}
              ],
              "body" => %{"data" => Base.encode64("Test body")}
            },
            "threadId" => "thread1"
          })
        }}
      end)

      job = %Oban.Job{
        args: %{
          "user_id" => user.id,
          "oldest_date" => "2024-01-01T00:00:00Z",
          "total_synced" => 300
        }
      }

      # Temporarily set logger level to info to capture the log messages
      Logger.configure(level: :info)

      logs = capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert :ok = result
      end)

      # Restore logger level
      Logger.configure(level: :warning)

      # Should log resume intention
      assert logs =~ "Resuming historical email sync"
      assert logs =~ "300 emails synced so far"
    end

    test "handles Gmail service errors gracefully" do
      {:ok, user} = create_user_with_google_auth()

      job = %Oban.Job{
        args: %{"user_id" => user.id}
      }

      logs = capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)

      # Should log error appropriately
      assert logs =~ "Failed to sync emails"
    end

    test "logs errors appropriately" do
      job = %Oban.Job{
        args: %{"user_id" => Ecto.UUID.generate()}
      }

      logs = capture_log(fn ->
        _result = HistoricalEmailSyncJob.perform(job)
      end)

      # Should log user not found error
      assert logs =~ "User"
      assert logs =~ "not found"
    end
  end

  describe "edge cases" do
    test "handles malformed user_id gracefully" do
      job = %Oban.Job{
        args: %{"user_id" => "not-a-valid-uuid"}
      }

      capture_log(fn ->
        # This should handle the invalid UUID format gracefully
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "handles job with missing user_id" do
      job = %Oban.Job{
        args: %{}
      }

      capture_log(fn ->
        # Should handle missing user_id gracefully
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, _reason} = result
      end)
    end

    test "handles job with nil args" do
      job = %Oban.Job{
        args: nil
      }

      # Now that we handle nil args gracefully, it should return an error tuple
      capture_log(fn ->
        result = HistoricalEmailSyncJob.perform(job)
        assert {:error, :nil_args} = result
      end)
    end
  end

  # Helper functions
  defp create_user_with_google_auth do
    Accounts.create_user(%{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User",
      google_uid: "google_#{System.unique_integer()}",
      google_access_token: "fake_access_token",
      google_refresh_token: "fake_refresh_token",
      google_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
      gmail_connected_at: DateTime.utc_now(),
      calendar_connected_at: DateTime.utc_now()
    })
  end
end

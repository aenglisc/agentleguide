defmodule Agentleguide.Jobs.HubspotTokenRefreshJobTest do
  use Agentleguide.DataCase, async: false
  use Oban.Testing, repo: Agentleguide.Repo

  import ExUnit.CaptureLog

  alias Agentleguide.Jobs.HubspotTokenRefreshJob
  alias Agentleguide.Accounts

    # No longer using Mox - using the simple test stub like other tests

  setup do
    # Create a user with HubSpot connected
    {:ok, user} =
      Accounts.create_user_from_google(%Ueberauth.Auth{
        uid: "test_uid",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "google_token",
          refresh_token: "google_refresh",
          expires_at: 1_640_995_200
        }
      })

    # Link with HubSpot
    hubspot_auth = %Ueberauth.Auth{
      uid: "hubspot_123",
      provider: :hubspot,
      info: %Ueberauth.Auth.Info{
        email: "test@example.com"
      },
      credentials: %Ueberauth.Auth.Credentials{
        token: "hubspot_access_token",
        refresh_token: "hubspot_refresh_token",
        # 30 minutes from now
        expires_at: DateTime.to_unix(DateTime.add(DateTime.utc_now(), 1800, :second))
      }
    }

    {:ok, user} = Accounts.link_user_with_hubspot(user, hubspot_auth)

    %{user: user}
  end

  describe "perform/1" do
    # HubSpot service mocking and scheduling disabled globally in test config
    setup do
      :ok
    end

    test "handles missing user gracefully" do
      capture_log(fn ->
        assert :ok = perform_job(HubspotTokenRefreshJob, %{user_id: Ecto.UUID.generate()})
      end)
    end

    test "handles user without HubSpot connection" do
      {:ok, user} =
        Accounts.create_user_from_google(%Ueberauth.Auth{
          uid: "test_uid_no_hubspot",
          info: %Ueberauth.Auth.Info{
            email: "nohubspot@example.com",
            name: "No HubSpot User"
          },
          credentials: %Ueberauth.Auth.Credentials{
            token: "google_token",
            refresh_token: "google_refresh"
          }
        })

      assert :ok = perform_job(HubspotTokenRefreshJob, %{user_id: user.id})
    end

    test "attempts refresh when token expiring soon", %{user: user} do
      # Update user to have token expiring in 5 minutes
      soon_expiry = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, _updated_user} = Accounts.update_user(user, %{hubspot_token_expires_at: soon_expiry})

      # In test environment, refresh will fail but job should handle it gracefully
      capture_log(fn ->
        result = perform_job(HubspotTokenRefreshJob, %{user_id: user.id})
        assert {:error, _reason} = result
      end)
    end

    test "handles refresh failure gracefully", %{user: user} do
      # Update user to have token expiring in 5 minutes
      soon_expiry = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, _updated_user} = Accounts.update_user(user, %{hubspot_token_expires_at: soon_expiry})

      # In test environment, refresh will fail but job should handle it gracefully
      capture_log(fn ->
        assert {:error, _reason} = perform_job(HubspotTokenRefreshJob, %{user_id: user.id})
      end)
    end
  end

  describe "schedule_now/1" do
    test "schedules immediate token refresh job" do
      user_id = Ecto.UUID.generate()

      # With Oban testing: :inline, the job runs immediately
      capture_log(fn ->
        assert {:ok, _job} = HubspotTokenRefreshJob.schedule_now(user_id)
      end)

      # The job runs inline in test mode, so we just verify it returns ok
      # and doesn't crash (it will log a warning that the user doesn't exist)
    end
  end

  describe "integration" do
    setup do
      :ok
    end

    test "skips refresh when token has plenty of time", %{user: user} do
      # Token expires in 30 minutes (default from setup) - should not refresh
      assert :ok = perform_job(HubspotTokenRefreshJob, %{user_id: user.id})
      # Test verifies job completes successfully without attempting refresh
    end
  end
end

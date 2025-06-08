defmodule Agentleguide.Jobs.HubspotTokenRefreshJobTest do
  use Agentleguide.DataCase
  use Oban.Testing, repo: Agentleguide.Repo

  import Mox
  import ExUnit.CaptureLog

  alias Agentleguide.Jobs.HubspotTokenRefreshJob
  alias Agentleguide.Accounts
  alias Agentleguide.HubspotServiceMock

  setup :verify_on_exit!

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

    test "successfully refreshes token when expiring soon", %{user: user} do
      # Update user to have token expiring in 5 minutes
      soon_expiry = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, updated_user} = Accounts.update_user(user, %{hubspot_token_expires_at: soon_expiry})

      # Mock successful refresh - expect only one call to the service
      new_user = %{updated_user | hubspot_access_token: "new_token"}

      expect(HubspotServiceMock, :refresh_access_token, 1, fn ^updated_user -> {:ok, new_user} end)

      assert :ok = perform_job(HubspotTokenRefreshJob, %{user_id: user.id})
    end

    test "handles refresh failure", %{user: user} do
      # Update user to have token expiring in 5 minutes
      soon_expiry = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, updated_user} = Accounts.update_user(user, %{hubspot_token_expires_at: soon_expiry})

      # Mock refresh failure - expect only one call to the service
      expect(HubspotServiceMock, :refresh_access_token, 1, fn ^updated_user ->
        {:error, :auth_failed}
      end)

      capture_log(fn ->
        assert {:error, :auth_failed} = perform_job(HubspotTokenRefreshJob, %{user_id: user.id})
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

      # Should not have called the refresh service at all
      verify!(HubspotServiceMock)
    end
  end
end

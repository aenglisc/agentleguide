defmodule Agentleguide.Services.Google.GoogleAuthServiceTest do
  use Agentleguide.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Agentleguide.Services.Google.GoogleAuthService
  alias Agentleguide.Accounts

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Create a user with Google tokens
    {:ok, user} =
      Accounts.create_user_from_google(%Ueberauth.Auth{
        uid: "test_uid",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "google_access_token",
          refresh_token: "google_refresh_token",
          expires_at: 1_640_995_200
        }
      })

    %{user: user}
  end

  describe "refresh_access_token/1" do
    test "handles user without refresh token", %{user: user} do
      # Remove refresh token
      {:ok, user_without_refresh} = Accounts.update_user(user, %{google_refresh_token: nil})

      capture_log(fn ->
        assert {:error, :no_refresh_token} = GoogleAuthService.refresh_access_token(user_without_refresh)
      end)
    end

    test "successfully refreshes token", %{user: user} do
      # Mock successful token refresh response
      expect(Agentleguide.GoogleAuthHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "access_token" => "new_access_token",
            "expires_in" => 3600
          })
        }}
      end)

      assert {:ok, updated_user} = GoogleAuthService.refresh_access_token(user)
      assert updated_user.google_access_token == "new_access_token"
      assert updated_user.google_token_expires_at != nil
    end

    test "handles API authentication failure", %{user: user} do
      # Mock auth failure response
      expect(Agentleguide.GoogleAuthHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      capture_log(fn ->
        assert {:error, :auth_failed} = GoogleAuthService.refresh_access_token(user)
      end)
    end

    test "handles invalid grant error", %{user: user} do
      # Mock invalid grant response
      expect(Agentleguide.GoogleAuthHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 400,
          body: Jason.encode!(%{"error" => "invalid_grant"})
        }}
      end)

      capture_log(fn ->
        assert {:error, :refresh_token_expired} = GoogleAuthService.refresh_access_token(user)
      end)
    end

    test "handles request timeout", %{user: user} do
      # Mock request failure
      expect(Agentleguide.GoogleAuthHttpMock, :request, fn _request, _finch_name ->
        {:error, :timeout}
      end)

      capture_log(fn ->
        assert {:error, {:request_failed, :timeout}} = GoogleAuthService.refresh_access_token(user)
      end)
    end
  end

  describe "needs_refresh?/1" do
    test "returns false when no expiry time is set", %{user: user} do
      {:ok, user_no_expiry} = Accounts.update_user(user, %{google_token_expires_at: nil})
      refute GoogleAuthService.needs_refresh?(user_no_expiry)
    end

    test "returns true when token expires soon", %{user: user} do
      # Set expiry to 2 minutes from now (less than 5 minute threshold)
      soon_expiry = DateTime.add(DateTime.utc_now(), 120, :second)
      {:ok, user_expiring} = Accounts.update_user(user, %{google_token_expires_at: soon_expiry})

      assert GoogleAuthService.needs_refresh?(user_expiring)
    end

    test "returns true when token is already expired", %{user: user} do
      # Set expiry to 10 minutes ago
      past_expiry = DateTime.add(DateTime.utc_now(), -600, :second)
      {:ok, user_expired} = Accounts.update_user(user, %{google_token_expires_at: past_expiry})

      assert GoogleAuthService.needs_refresh?(user_expired)
    end

    test "returns false when token has plenty of time left", %{user: user} do
      # Set expiry to 30 minutes from now (more than 5 minute threshold)
      future_expiry = DateTime.add(DateTime.utc_now(), 1800, :second)
      {:ok, user_valid} = Accounts.update_user(user, %{google_token_expires_at: future_expiry})

      refute GoogleAuthService.needs_refresh?(user_valid)
    end

    test "returns true exactly at 5 minute threshold", %{user: user} do
      # Set expiry to exactly 5 minutes (300 seconds) from now
      threshold_expiry = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, user_threshold} = Accounts.update_user(user, %{google_token_expires_at: threshold_expiry})

      assert GoogleAuthService.needs_refresh?(user_threshold)
    end
  end

  describe "check_and_refresh_if_needed/1" do
    test "returns user unchanged when token doesn't need refresh", %{user: user} do
      # Set expiry to 30 minutes from now
      future_expiry = DateTime.add(DateTime.utc_now(), 1800, :second)
      {:ok, user_valid} = Accounts.update_user(user, %{google_token_expires_at: future_expiry})

      assert {:ok, ^user_valid} = GoogleAuthService.check_and_refresh_if_needed(user_valid)
    end

    test "attempts refresh when token needs refresh", %{user: user} do
      # Set expiry to 2 minutes from now
      soon_expiry = DateTime.add(DateTime.utc_now(), 120, :second)
      {:ok, user_expiring} = Accounts.update_user(user, %{google_token_expires_at: soon_expiry})

      # Mock successful token refresh
      expect(Agentleguide.GoogleAuthHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "access_token" => "refreshed_access_token",
            "expires_in" => 3600
          })
        }}
      end)

      assert {:ok, updated_user} = GoogleAuthService.check_and_refresh_if_needed(user_expiring)
      assert updated_user.google_access_token == "refreshed_access_token"
    end

    test "handles refresh failure gracefully", %{user: user} do
      # Set expiry to trigger refresh and remove refresh token to cause failure
      soon_expiry = DateTime.add(DateTime.utc_now(), 120, :second)
      {:ok, user_bad} = Accounts.update_user(user, %{
        google_token_expires_at: soon_expiry,
        google_refresh_token: nil
      })

      capture_log(fn ->
        assert {:error, :no_refresh_token} = GoogleAuthService.check_and_refresh_if_needed(user_bad)
      end)
    end
  end

  describe "debug_token_status/1" do
    test "returns no_expiry_set status when expiry is nil", %{user: user} do
      {:ok, user_no_expiry} = Accounts.update_user(user, %{google_token_expires_at: nil})

      assert {:ok, status} = GoogleAuthService.debug_token_status(user_no_expiry)
      assert status.status == :no_expiry_set
      assert status.has_access_token == true
      assert status.has_refresh_token == true
    end

        test "returns expired status for past expiry time", %{user: user} do
      past_expiry = DateTime.add(DateTime.utc_now(), -600, :second)
      {:ok, user_expired} = Accounts.update_user(user, %{google_token_expires_at: past_expiry})

      assert {:ok, status} = GoogleAuthService.debug_token_status(user_expired)
      assert status.status == :expired
      # Database may truncate microseconds, so check if times are close
      assert DateTime.diff(status.expires_at, past_expiry, :second) == 0
      assert status.seconds_until_expiry < 0
      assert status.has_access_token == true
      assert status.has_refresh_token == true
    end

        test "returns expiring_soon status for near-future expiry", %{user: user} do
      soon_expiry = DateTime.add(DateTime.utc_now(), 120, :second)
      {:ok, user_expiring} = Accounts.update_user(user, %{google_token_expires_at: soon_expiry})

      assert {:ok, status} = GoogleAuthService.debug_token_status(user_expiring)
      assert status.status == :expiring_soon
      # Database may truncate microseconds, so check if times are close
      assert DateTime.diff(status.expires_at, soon_expiry, :second) == 0
      assert status.seconds_until_expiry > 0
      assert status.seconds_until_expiry <= 300
    end

        test "returns valid status for future expiry", %{user: user} do
      future_expiry = DateTime.add(DateTime.utc_now(), 1800, :second)
      {:ok, user_valid} = Accounts.update_user(user, %{google_token_expires_at: future_expiry})

      assert {:ok, status} = GoogleAuthService.debug_token_status(user_valid)
      assert status.status == :valid
      # Database may truncate microseconds, so check if times are close
      assert DateTime.diff(status.expires_at, future_expiry, :second) == 0
      assert status.seconds_until_expiry > 300
    end

    test "correctly reports token availability", %{user: user} do
      # Test user with no tokens
      {:ok, user_no_tokens} = Accounts.update_user(user, %{
        google_access_token: nil,
        google_refresh_token: nil,
        google_token_expires_at: nil
      })

      assert {:ok, status} = GoogleAuthService.debug_token_status(user_no_tokens)
      assert status.has_access_token == false
      assert status.has_refresh_token == false
    end

    test "handles edge case at exactly 5 minute mark", %{user: user} do
      # Test exactly at the 300 second boundary
      threshold_expiry = DateTime.add(DateTime.utc_now(), 300, :second)
      {:ok, user_threshold} = Accounts.update_user(user, %{google_token_expires_at: threshold_expiry})

      assert {:ok, status} = GoogleAuthService.debug_token_status(user_threshold)
      assert status.status == :expiring_soon
      assert status.seconds_until_expiry <= 300
    end
  end

  describe "integration scenarios" do
    test "full workflow: check status, detect need for refresh, attempt refresh" do
      # Create user with expiring token
      soon_expiry = DateTime.add(DateTime.utc_now(), 120, :second)
      {:ok, user_expiring} = Accounts.update_user(user_fixture(), %{
        google_token_expires_at: soon_expiry
      })

      # Check debug status
      assert {:ok, debug_status} = GoogleAuthService.debug_token_status(user_expiring)
      assert debug_status.status == :expiring_soon

      # Check if needs refresh
      assert GoogleAuthService.needs_refresh?(user_expiring) == true

      # Mock token refresh failure
      expect(Agentleguide.GoogleAuthHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      # Attempt refresh (will fail with auth error)
      capture_log(fn ->
        assert {:error, :auth_failed} = GoogleAuthService.check_and_refresh_if_needed(user_expiring)
      end)
    end

    test "user with valid token requires no action" do
      # Create user with valid token
      future_expiry = DateTime.add(DateTime.utc_now(), 3600, :second)
      {:ok, user_valid} = Accounts.update_user(user_fixture(), %{
        google_token_expires_at: future_expiry
      })

      # Check debug status
      assert {:ok, debug_status} = GoogleAuthService.debug_token_status(user_valid)
      assert debug_status.status == :valid

      # Check if needs refresh
      assert GoogleAuthService.needs_refresh?(user_valid) == false

      # No refresh needed
      assert {:ok, ^user_valid} = GoogleAuthService.check_and_refresh_if_needed(user_valid)
    end
  end

  # Helper function to create a user for testing
  defp user_fixture do
    {:ok, user} =
      Accounts.create_user_from_google(%Ueberauth.Auth{
        uid: "fixture_test_uid_#{System.unique_integer()}",
        info: %Ueberauth.Auth.Info{
          email: "fixture_test_#{System.unique_integer()}@example.com",
          name: "Fixture Test User"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "google_access_token",
          refresh_token: "google_refresh_token"
        }
      })

    user
  end
end

defmodule AgentleguideWeb.AuthControllerTest do
  use AgentleguideWeb.ConnCase

  alias Agentleguide.Accounts

  describe "Google OAuth callback" do
    def mock_google_auth_assign(conn, auth_data \\ %{}) do
      default_auth = %Ueberauth.Auth{
        uid: "123456789",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "access_token_123",
          refresh_token: "refresh_token_123",
          expires_at: 1640995200
        }
      }

      auth = Map.merge(default_auth, auth_data)
      assign(conn, :ueberauth_auth, auth)
    end

    def mock_google_auth_failure(conn, failure_data \\ %{}) do
      default_failure = %Ueberauth.Failure{
        provider: :google,
        strategy: Ueberauth.Strategy.Google,
        errors: [
          %Ueberauth.Failure.Error{
            message_key: "oauth_error",
            message: "OAuth authentication failed"
          }
        ]
      }

      failure = Map.merge(default_failure, failure_data)
      assign(conn, :ueberauth_failure, failure)
    end

    test "successful Google OAuth creates user and redirects", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> mock_google_auth_assign()

      # Call the controller method directly instead of going through the route
      conn = AgentleguideWeb.AuthController.callback(conn, %{})

      assert redirected_to(conn) == "/"

      # Check that user was created
      user = Accounts.get_user_by_email("test@example.com")
      assert user != nil
      assert user.google_uid == "123456789"
      assert user.gmail_connected_at != nil
      assert user.calendar_connected_at != nil
    end

    test "successful OAuth updates existing user tokens", %{conn: conn} do
      # Create an existing user first
      {:ok, existing_user} =
        Accounts.create_user_from_google(%Ueberauth.Auth{
          uid: "123456789",
          info: %Ueberauth.Auth.Info{
            email: "test@example.com",
            name: "Test User",
            image: "https://example.com/avatar.jpg"
          },
          credentials: %Ueberauth.Auth.Credentials{
            token: "old_access_token",
            refresh_token: "old_refresh_token",
            expires_at: 1640995200
          }
        })

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> mock_google_auth_assign(%{
          credentials: %Ueberauth.Auth.Credentials{
            token: "new_access_token",
            refresh_token: "new_refresh_token",
            expires_at: 1640995200
          }
        })

      # Call the controller method directly instead of going through the route
      conn = AgentleguideWeb.AuthController.callback(conn, %{})

      assert redirected_to(conn) == "/"

      # Check that tokens were updated
      updated_user = Accounts.get_user!(existing_user.id)
      assert updated_user.google_access_token == "new_access_token"
      assert updated_user.google_refresh_token == "new_refresh_token"
    end

    test "OAuth failure redirects with error", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> mock_google_auth_failure()

      conn = get(conn, "/auth/google/callback")

      assert redirected_to(conn) == "/"
    end

    test "OAuth failure does not create user", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> mock_google_auth_failure()

      get(conn, "/auth/google/callback")

      # Check that no user was created
      user = Accounts.get_user_by_email("test@example.com")
      assert user == nil
    end
  end

  describe "logout" do
    test "logout redirects to home", %{conn: conn} do
      # Set up a user session first
      {:ok, user} =
        Accounts.create_user_from_google(%Ueberauth.Auth{
          uid: "123456789",
          info: %Ueberauth.Auth.Info{
            email: "test@example.com",
            name: "Test User",
            image: "https://example.com/avatar.jpg"
          },
          credentials: %Ueberauth.Auth.Credentials{
            token: "access_token_123",
            refresh_token: "refresh_token_123",
            expires_at: 1640995200
          }
        })

      conn =
        conn
        |> init_test_session(%{user_id: user.id})

      conn = delete(conn, "/auth/logout")

      assert redirected_to(conn) == "/"
    end
  end

  describe "authentication helper functions" do
    setup do
      {:ok, user} =
        Accounts.create_user_from_google(%Ueberauth.Auth{
          uid: "123456789",
          info: %Ueberauth.Auth.Info{
            email: "test@example.com",
            name: "Test User",
            image: "https://example.com/avatar.jpg"
          },
          credentials: %Ueberauth.Auth.Credentials{
            token: "access_token_123",
            refresh_token: "refresh_token_123",
            expires_at: 1640995200
          }
        })

      %{user: user}
    end

    test "fetch_current_user assigns current_user when session exists", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> get("/")

      assert conn.assigns.current_user.id == user.id
    end

    test "fetch_current_user assigns nil when no session", %{conn: conn} do
      conn = get(conn, "/")
      assert conn.assigns.current_user == nil
    end

    test "fetch_current_user clears session when user doesn't exist", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> init_test_session(%{user_id: fake_id})
        |> get("/")

      assert conn.assigns.current_user == nil
    end
  end
end

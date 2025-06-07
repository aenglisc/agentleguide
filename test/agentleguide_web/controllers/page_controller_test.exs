defmodule AgentleguideWeb.PageControllerTest do
  use AgentleguideWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "AI Financial Advisor Assistant"
    assert html_response(conn, 200) =~ "Account Connections"
    assert html_response(conn, 200) =~ "Connect with Google"
  end

  test "GET / with authenticated user", %{conn: conn} do
    # Create a user
    {:ok, user} =
      Agentleguide.Accounts.create_user_from_google(%Ueberauth.Auth{
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
      |> get("/")

    assert html_response(conn, 200) =~ "test@example.com"
    assert html_response(conn, 200) =~ "Connected"
    assert html_response(conn, 200) =~ "Sign out"
  end
end

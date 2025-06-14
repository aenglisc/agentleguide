defmodule AgentleguideWeb.AuthControllerHubspotTest do
  use AgentleguideWeb.ConnCase

  alias Agentleguide.Accounts

  describe "HubSpot OAuth" do
    setup do
      # HubSpot scheduling and API calls disabled globally in test config
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
            expires_at: 1_640_995_200
          }
        })

      %{user: user}
    end

    test "hubspot_request redirects to HubSpot OAuth when user is logged in", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> fetch_flash()
        |> assign(:current_user, user)
        |> get("/auth/hubspot")

      assert redirected_to(conn, 302)
      # The actual URL will be generated by ueberauth_hubspot
      assert Plug.Conn.get_resp_header(conn, "location") != []
    end

    test "hubspot_request redirects to home when user is not logged in", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, nil)
        |> get("/auth/hubspot")

      assert redirected_to(conn, 302)
    end

    test "hubspot_callback links user with HubSpot account", %{conn: conn, user: user} do
      hubspot_auth = %Ueberauth.Auth{
        uid: "hubspot_123",
        provider: :hubspot,
        info: %Ueberauth.Auth.Info{
          email: "test@example.com"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "hubspot_access_token",
          refresh_token: "hubspot_refresh_token",
          expires_at: 1_640_995_200
        }
      }

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> fetch_flash()
        |> assign(:current_user, user)
        |> assign(:ueberauth_auth, hubspot_auth)

      # Call the controller method directly
      conn = AgentleguideWeb.AuthController.callback(conn, %{"provider" => "hubspot"})

      assert redirected_to(conn) == "/"
      flash_info = Phoenix.Flash.get(conn.assigns.flash, :info)
      assert flash_info != nil
      assert flash_info =~ "Successfully connected your HubSpot account"

      # Verify user was updated
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.hubspot_access_token == "hubspot_access_token"
      assert updated_user.hubspot_refresh_token == "hubspot_refresh_token"
      assert updated_user.hubspot_connected_at != nil
    end

    test "hubspot_callback handles missing user", %{conn: conn} do
      hubspot_auth = %Ueberauth.Auth{
        uid: "hubspot_123",
        provider: :hubspot,
        info: %Ueberauth.Auth.Info{
          email: "test@example.com"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "hubspot_access_token",
          refresh_token: "hubspot_refresh_token",
          expires_at: 1_640_995_200
        }
      }

      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_user, nil)
        |> assign(:ueberauth_auth, hubspot_auth)

      # Call the controller method directly
      conn = AgentleguideWeb.AuthController.callback(conn, %{"provider" => "hubspot"})

      assert redirected_to(conn) == "/"
      flash_error = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash_error != nil
      assert flash_error =~ "You must be logged in"
    end

    test "hubspot_callback handles OAuth failure", %{conn: conn, user: user} do
      failure = %Ueberauth.Failure{
        provider: :hubspot,
        strategy: Ueberauth.Strategy.Hubspot,
        errors: [
          %Ueberauth.Failure.Error{
            message_key: "missing_code",
            message: "No authorization code received"
          }
        ]
      }

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> fetch_flash()
        |> assign(:current_user, user)
        |> assign(:ueberauth_failure, failure)

      # Call the controller method directly
      conn = AgentleguideWeb.AuthController.callback(conn, %{"provider" => "hubspot"})

      assert redirected_to(conn) == "/"
      flash_error = Phoenix.Flash.get(conn.assigns.flash, :error)
      assert flash_error != nil
      assert flash_error =~ "Failed to authenticate with Hubspot"
    end
  end
end

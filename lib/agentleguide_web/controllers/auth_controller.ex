defmodule AgentleguideWeb.AuthController do
  use AgentleguideWeb, :controller
  plug Ueberauth

  alias Agentleguide.Accounts

  def request(conn, _params) do
    # Ueberauth will handle the redirect to the OAuth provider
    # This action is typically not reached as Ueberauth redirects beforehand
    redirect(conn, to: ~p"/")
  end

    def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, %{"provider" => provider}) do
    conn
    |> put_flash(
      :error,
      "Failed to authenticate with #{String.capitalize(provider)}. Please try again."
    )
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => "google"}) do
    case Accounts.find_or_create_user_from_google(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully connected with Google!")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          "There was an issue connecting your Google account. Please try again."
        )
        |> redirect(to: ~p"/")
    end
  end

    def callback(%{assigns: %{ueberauth_auth: auth}} = conn, %{"provider" => "hubspot"}) do
    current_user = conn.assigns.current_user

    if current_user do
      case Accounts.link_user_with_hubspot(current_user, auth) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Successfully connected your HubSpot account!")
          |> redirect(to: ~p"/")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Failed to save HubSpot connection. Please try again.")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "You must be logged in to connect HubSpot.")
      |> redirect(to: ~p"/")
    end
  end

  # Fallback for tests and other cases where provider is not in params
  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # Default to Google OAuth for backwards compatibility
    case Accounts.find_or_create_user_from_google(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully connected with Google!")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          "There was an issue connecting your Google account. Please try again."
        )
        |> redirect(to: ~p"/")
    end
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out!")
    |> redirect(to: ~p"/")
  end

  def disconnect(conn, %{"provider" => "hubspot"}) do
    current_user = conn.assigns.current_user

    if current_user do
      case Accounts.disconnect_user_from_hubspot(current_user) do
        {:ok, _user} ->
          conn
          |> put_flash(:info, "Successfully disconnected from HubSpot!")
          |> redirect(to: ~p"/")

        {:error, _changeset} ->
          conn
          |> put_flash(:error, "Failed to disconnect from HubSpot. Please try again.")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "You must be logged in to disconnect integrations.")
      |> redirect(to: ~p"/")
    end
  end

  def disconnect(conn, %{"provider" => provider}) do
    conn
    |> put_flash(:error, "Disconnecting from #{String.capitalize(provider)} is not supported yet.")
    |> redirect(to: ~p"/")
  end


end

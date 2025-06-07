defmodule AgentleguideWeb.AuthController do
  use AgentleguideWeb, :controller
  plug Ueberauth

  alias Agentleguide.Accounts

  def request(conn, _params) do
    # Ueberauth will handle the redirect to the OAuth provider
    # This action is typically not reached as Ueberauth redirects beforehand
    redirect(conn, to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate with Google. Please try again.")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.find_or_create_user_from_google(auth) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Successfully connected with Google!")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "There was an issue connecting your Google account. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out!")
    |> redirect(to: ~p"/")
  end
end

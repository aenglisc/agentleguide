defmodule AgentleguideWeb.Router do
  use AgentleguideWeb, :router
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentleguideWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Authentication pipelines
  pipeline :require_auth do
    plug :require_authenticated_user
  end

  pipeline :require_no_auth do
    plug :redirect_if_user_is_authenticated
  end

  scope "/auth", AgentleguideWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
    delete "/disconnect/:provider", AuthController, :disconnect
  end

  scope "/", AgentleguideWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/profile-image/:user_id", PageController, :profile_image
  end

  # Other scopes may use custom stacks.
  # scope "/api", AgentleguideWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:agentleguide, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgentleguideWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Authentication helpers
  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      user = Agentleguide.Accounts.get_user!(user_id)
      assign(conn, :current_user, user)
    else
      assign(conn, :current_user, nil)
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> configure_session(drop: true)
      |> assign(:current_user, nil)
  end

  defp require_authenticated_user(conn, _opts) do
    if conn.assigns.current_user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end

  defp redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns.current_user do
      conn
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end
end

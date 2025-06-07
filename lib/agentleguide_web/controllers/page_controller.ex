defmodule AgentleguideWeb.PageController do
  use AgentleguideWeb, :controller

  def home(conn, _params) do
    current_user = conn.assigns[:current_user]
    render(conn, :home, current_user: current_user)
  end
end

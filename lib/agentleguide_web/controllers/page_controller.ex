defmodule AgentleguideWeb.PageController do
  use AgentleguideWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

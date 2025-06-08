defmodule AgentleguideWeb.PageController do
  use AgentleguideWeb, :controller

  def home(conn, _params) do
    current_user = conn.assigns[:current_user]
    render(conn, :home, current_user: current_user)
  end

  def profile_image(conn, %{"user_id" => user_id}) do
    current_user = conn.assigns[:current_user]

    # Only allow users to access their own profile image
    if current_user && current_user.id == user_id && current_user.avatar_url do
      case fetch_and_proxy_image(current_user.avatar_url) do
        {:ok, image_data, content_type} ->
          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("cache-control", "public, max-age=3600")
          |> send_resp(200, image_data)

        {:error, _reason} ->
          conn
          |> put_status(404)
          |> put_view(html: AgentleguideWeb.ErrorHTML)
          |> render(:"404")
      end
    else
      conn
      |> put_status(404)
      |> put_view(html: AgentleguideWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  defp fetch_and_proxy_image(url) do
    headers = [
      {"user-agent", "AgentLeGuide/1.0"},
      {"referer", "https://accounts.google.com/"}
    ]

    request = Finch.build(:get, url, headers)

    case Finch.request(request, Agentleguide.Finch, receive_timeout: 5000) do
      {:ok, %Finch.Response{status: 200, body: body, headers: headers}} ->
        content_type =
          headers
          |> Enum.find(fn {key, _} -> String.downcase(key) == "content-type" end)
          |> case do
            {_, type} -> type
            nil -> "image/jpeg"
          end

        {:ok, body, content_type}

      _ ->
        {:error, :fetch_failed}
    end
  end
end

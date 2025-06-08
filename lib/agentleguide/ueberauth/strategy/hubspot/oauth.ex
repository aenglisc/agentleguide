defmodule Ueberauth.Strategy.Hubspot.OAuth do
  @moduledoc """
  OAuth2 client for HubSpot.
  """

  use OAuth2.Strategy

  def base_api_url(), do: Application.get_env(:agentleguide, :hubspot_base_api_url)

  defp defaults() do
    base_url = base_api_url()

    [
      strategy: __MODULE__,
      site: "https://app.hubspot.com",
      authorize_url: "https://app.hubspot.com/oauth/authorize",
      token_url: "#{base_url}/oauth/v1/token",
      token_method: :post
    ]
  end

  def client(opts \\ []) do
    config = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)
    client_opts = defaults() |> Keyword.merge(config) |> Keyword.merge(opts)
    json_library = Ueberauth.json_library()

    client_opts
    |> OAuth2.Client.new()
    |> OAuth2.Client.put_serializer("application/json", json_library)
  end

  def get(url) do
    OAuth2.Client.get(client(), url)
  end

  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  def get_token!(params \\ [], opts \\ []) do
    client =
      opts
      |> client()
      |> OAuth2.Client.get_token!(params)

    client.token
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_header("Accept", "application/json")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end

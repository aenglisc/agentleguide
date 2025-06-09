defmodule Agentleguide.Services.Google.GoogleAuthService do
  @moduledoc """
  Service for handling Google OAuth token management and refresh.
  """

  require Logger
  alias Agentleguide.Accounts

  @google_token_url "https://oauth2.googleapis.com/token"

  defp http_client do
    Application.get_env(:agentleguide, :google_auth_http_client, Finch)
  end

  @doc """
  Refresh the Google access token using the refresh token.
  Google access tokens expire after 1 hour.
  """
  def refresh_access_token(user) do
    if user.google_refresh_token do
      body = %{
        "grant_type" => "refresh_token",
        "client_id" => System.get_env("GOOGLE_CLIENT_ID"),
        "client_secret" => System.get_env("GOOGLE_CLIENT_SECRET"),
        "refresh_token" => user.google_refresh_token
      }

      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      # Google expects form-encoded data for token refresh
      form_body = URI.encode_query(body)
      request = Finch.build(:post, @google_token_url, headers, form_body)

      case http_client().request(request, Agentleguide.Finch) do
        {:ok, %{status: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"access_token" => access_token, "expires_in" => expires_in} = token_data} ->
              # Calculate expiry time
              expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

              # Update user with new token
              user_params = %{
                google_access_token: access_token,
                google_token_expires_at: expires_at
              }

              # Update refresh token if provided (Google may issue a new one)
              user_params =
                if token_data["refresh_token"] do
                  Map.put(user_params, :google_refresh_token, token_data["refresh_token"])
                else
                  user_params
                end

              case Accounts.update_user(user, user_params) do
                {:ok, updated_user} ->
                  Logger.info("Successfully refreshed Google token for user #{user.id}")
                  {:ok, updated_user}

                {:error, changeset} ->
                  Logger.error(
                    "Failed to update user with new Google token: #{inspect(changeset)}"
                  )

                  {:error, :update_failed}
              end

            {:error, error} ->
              Logger.error("Failed to parse Google token refresh response: #{inspect(error)}")
              {:error, :json_decode_error}
          end

        {:ok, %{status: 400, body: response_body}} ->
          Logger.error("Google token refresh failed with 400: #{response_body}")

          case Jason.decode(response_body) do
            {:ok, %{"error" => "invalid_grant"}} ->
              # Refresh token is invalid/expired - user needs to reconnect
              Logger.error("Google refresh token expired for user #{user.id}")
              {:error, :refresh_token_expired}

            _ ->
              {:error, :bad_request}
          end

        {:ok, %{status: 401}} ->
          Logger.error("Google token refresh authentication failed for user #{user.id}")
          {:error, :auth_failed}

        {:ok, %{status: status, body: response_body}} ->
          Logger.error("Google token refresh failed with status #{status}: #{response_body}")
          {:error, {:api_error, status}}

        {:error, error} ->
          Logger.error("Google token refresh request failed: #{inspect(error)}")
          {:error, {:request_failed, error}}
      end
    else
      Logger.warning(
        "Cannot refresh Google token for user #{user.id}: no refresh token available"
      )

      {:error, :no_refresh_token}
    end
  end

  @doc """
  Check if a user's Google token needs refresh (expires in next 5 minutes)
  """
  def needs_refresh?(user) do
    case user.google_token_expires_at do
      nil ->
        false

      expiry_time ->
        seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())
        seconds_until_expiry <= 300
    end
  end

  @doc """
  Check and refresh Google token if needed.
  Returns updated user or original user if no refresh needed.
  """
  def check_and_refresh_if_needed(user) do
    if needs_refresh?(user) do
      case refresh_access_token(user) do
        {:ok, updated_user} ->
          Logger.debug("Auto-refreshed Google token for user #{user.id}")
          {:ok, updated_user}

        {:error, reason} ->
          Logger.warning(
            "Failed to auto-refresh Google token for user #{user.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      {:ok, user}
    end
  end

  @doc """
  Debug token status for troubleshooting.
  """
  def debug_token_status(user) do
    case user.google_token_expires_at do
      nil ->
        {:ok,
         %{
           status: :no_expiry_set,
           has_access_token: !is_nil(user.google_access_token),
           has_refresh_token: !is_nil(user.google_refresh_token)
         }}

      expiry_time ->
        seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())

        status =
          cond do
            seconds_until_expiry <= 0 -> :expired
            seconds_until_expiry <= 300 -> :expiring_soon
            true -> :valid
          end

        {:ok,
         %{
           status: status,
           expires_at: expiry_time,
           seconds_until_expiry: seconds_until_expiry,
           has_access_token: !is_nil(user.google_access_token),
           has_refresh_token: !is_nil(user.google_refresh_token)
         }}
    end
  end
end

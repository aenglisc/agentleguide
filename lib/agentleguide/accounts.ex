defmodule Agentleguide.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Agentleguide.Repo
  alias Agentleguide.Accounts.User

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("user@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by Google UID.

  ## Examples

      iex> get_user_by_google_uid("123456789")
      %User{}

      iex> get_user_by_google_uid("unknown")
      nil

  """
  def get_user_by_google_uid(google_uid) when is_binary(google_uid) do
    Repo.get_by(User, google_uid: google_uid)
  end

  @doc """
  Creates a user from Google OAuth data.

  ## Examples

      iex> create_user_from_google(auth)
      {:ok, %User{}}

      iex> create_user_from_google(bad_auth)
      {:error, %Ecto.Changeset{}}

  """
  def create_user_from_google(%Ueberauth.Auth{} = auth) do
    %{
      uid: google_uid,
      info: %{
        email: email,
        name: name,
        image: avatar_url
      },
      credentials: %{
        token: access_token,
        refresh_token: refresh_token,
        expires_at: expires_at
      }
    } = auth

    expires_at =
      if expires_at do
        DateTime.from_unix!(expires_at)
      else
        nil
      end

    user_params = %{
      email: email,
      name: name,
      avatar_url: avatar_url,
      google_uid: google_uid,
      google_access_token: access_token,
      google_refresh_token: refresh_token,
      google_token_expires_at: expires_at,
      gmail_connected_at: DateTime.utc_now(),
      calendar_connected_at: DateTime.utc_now()
    }

    %User{}
    |> User.changeset(user_params)
    |> Repo.insert()
  end

  @doc """
  Updates a user's Google OAuth tokens.

  ## Examples

      iex> update_user_google_tokens(user, auth)
      {:ok, %User{}}

      iex> update_user_google_tokens(user, bad_auth)
      {:error, %Ecto.Changeset{}}

  """
  def update_user_google_tokens(%User{} = user, %Ueberauth.Auth{} = auth) do
    %{
      credentials: %{
        token: access_token,
        refresh_token: refresh_token,
        expires_at: expires_at
      }
    } = auth

    expires_at =
      if expires_at do
        DateTime.from_unix!(expires_at)
      else
        nil
      end

    user_params = %{
      google_access_token: access_token,
      google_refresh_token: refresh_token || user.google_refresh_token,
      google_token_expires_at: expires_at,
      gmail_connected_at: DateTime.utc_now(),
      calendar_connected_at: DateTime.utc_now()
    }

    user
    |> User.changeset(user_params)
    |> Repo.update()
  end

  @doc """
  Finds or creates a user from Google OAuth data.

  ## Examples

      iex> find_or_create_user_from_google(auth)
      {:ok, %User{}}

  """
  def find_or_create_user_from_google(%Ueberauth.Auth{} = auth) do
    %{uid: google_uid, info: %{email: email}} = auth

    case get_user_by_google_uid(google_uid) do
      %User{} = user ->
        update_user_google_tokens(user, auth)

      nil ->
        case get_user_by_email(email) do
          %User{} = user ->
            # Link existing user with Google account
            user_params = %{
              google_uid: google_uid,
              google_access_token: auth.credentials.token,
              google_refresh_token: auth.credentials.refresh_token,
              google_token_expires_at:
                if auth.credentials.expires_at do
                  DateTime.from_unix!(auth.credentials.expires_at)
                else
                  nil
                end,
              gmail_connected_at: DateTime.utc_now(),
              calendar_connected_at: DateTime.utc_now()
            }

            user
            |> User.changeset(user_params)
            |> Repo.update()

          nil ->
            create_user_from_google(auth)
        end
    end
  end
end

defmodule Agentleguide.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Agentleguide.Repo
  alias Agentleguide.Accounts.User

  @doc """
  Gets a single user.

  Returns nil if the User does not exist.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user(456)
      nil

  """
  def get_user(id), do: Repo.get(User, id)

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
  Gets a single user by Google UID.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user_by_google_uid("123456")
      %User{}

      iex> get_user_by_google_uid("invalid")
      nil

  """
  def get_user_by_google_uid(google_uid) do
    Repo.get_by(User, google_uid: google_uid)
  end

  @doc """
  Creates a user with the given attributes.

  ## Examples

      iex> create_user(%{email: "test@example.com", name: "Test User"})
      {:ok, %User{}}

      iex> create_user(%{email: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
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

    result = %User{}
    |> User.changeset(user_params)
    |> Repo.insert()

    # Trigger historical email sync for new users
    case result do
      {:ok, user} ->
        Agentleguide.Jobs.HistoricalEmailSyncJob.queue_historical_sync(user)
        result
      error ->
        error
    end
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
      info: %{
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
      name: name || user.name,
      avatar_url: avatar_url || user.avatar_url,
      google_access_token: access_token,
      google_refresh_token: refresh_token || user.google_refresh_token,
      google_token_expires_at: expires_at,
      gmail_connected_at: DateTime.utc_now(),
      calendar_connected_at: DateTime.utc_now()
    }

    result = user
    |> User.changeset(user_params)
    |> Repo.update()

    # Trigger historical email sync when tokens are updated (reconnection)
    case result do
      {:ok, updated_user} ->
        Agentleguide.Jobs.HistoricalEmailSyncJob.queue_historical_sync(updated_user)
        result
      error ->
        error
    end
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
              name: auth.info.name || user.name,
              avatar_url: auth.info.image || user.avatar_url,
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

            result = user
            |> User.changeset(user_params)
            |> Repo.update()

            # Trigger historical email sync when linking existing user with Google
            case result do
              {:ok, updated_user} ->
                Agentleguide.Jobs.HistoricalEmailSyncJob.queue_historical_sync(updated_user)
                result
              error ->
                error
            end

          nil ->
            create_user_from_google(auth)
        end
    end
  end

  @doc """
  Links a user with HubSpot OAuth data.

  ## Examples

      iex> link_user_with_hubspot(user, auth)
      {:ok, %User{}}

      iex> link_user_with_hubspot(user, bad_auth)
      {:error, %Ecto.Changeset{}}

  """
  def link_user_with_hubspot(%User{} = user, %Ueberauth.Auth{} = auth) do
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
      hubspot_access_token: access_token,
      hubspot_refresh_token: refresh_token,
      hubspot_token_expires_at: expires_at,
      hubspot_connected_at: DateTime.utc_now()
    }

    user
    |> User.changeset(user_params)
    |> Repo.update()
  end

  @doc """
  Disconnects a user from HubSpot by clearing all HubSpot-related data.

  ## Examples

      iex> disconnect_user_from_hubspot(user)
      {:ok, %User{}}

      iex> disconnect_user_from_hubspot(user)
      {:error, %Ecto.Changeset{}}

  """
  def disconnect_user_from_hubspot(%User{} = user) do
    user_params = %{
      hubspot_access_token: nil,
      hubspot_refresh_token: nil,
      hubspot_token_expires_at: nil,
      hubspot_connected_at: nil
    }

    user
    |> User.changeset(user_params)
    |> Repo.update()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end
end

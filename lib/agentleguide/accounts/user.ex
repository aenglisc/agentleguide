defmodule Agentleguide.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :avatar_url, :string

    # Google OAuth fields
    field :google_uid, :string
    field :google_access_token, :string
    field :google_refresh_token, :string
    field :google_token_expires_at, :utc_datetime

    # Integration status
    field :gmail_connected_at, :utc_datetime
    field :calendar_connected_at, :utc_datetime
    field :hubspot_connected_at, :utc_datetime

    # HubSpot OAuth fields
    field :hubspot_access_token, :string
    field :hubspot_refresh_token, :string
    field :hubspot_token_expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :avatar_url,
      :google_uid,
      :google_access_token,
      :google_refresh_token,
      :google_token_expires_at,
      :gmail_connected_at,
      :calendar_connected_at,
      :hubspot_connected_at,
      :hubspot_access_token,
      :hubspot_refresh_token,
      :hubspot_token_expires_at
    ])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
    |> unique_constraint(:google_uid)
  end

  @doc """
  A changeset for updating Google OAuth tokens.
  """
  def google_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :google_uid,
      :google_access_token,
      :google_refresh_token,
      :google_token_expires_at,
      :gmail_connected_at,
      :calendar_connected_at
    ])
    |> validate_required([:google_uid, :google_access_token])
  end

  @doc """
  A changeset for updating HubSpot OAuth tokens.
  """
  def hubspot_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :hubspot_access_token,
      :hubspot_refresh_token,
      :hubspot_token_expires_at,
      :hubspot_connected_at
    ])
    |> validate_required([:hubspot_access_token])
  end
end

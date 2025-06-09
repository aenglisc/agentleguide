defmodule Agentleguide.Accounts.UserTest do
  use Agentleguide.DataCase

  alias Agentleguide.Accounts.User

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{email: "test@example.com", name: "Test User"}
      changeset = User.changeset(%User{}, attrs)

      assert changeset.valid?
      assert changeset.changes.email == "test@example.com"
      assert changeset.changes.name == "Test User"
    end

    test "requires email" do
      attrs = %{name: "Test User"}
      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on_changeset(changeset).email
    end

        test "validates email format" do
      attrs = %{email: "invalid-email", name: "Test User"}
      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on_changeset(changeset).email
    end

    test "validates email with spaces" do
      attrs = %{email: "test @example.com", name: "Test User"}
      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "must have the @ sign and no spaces" in errors_on_changeset(changeset).email
    end

    test "validates email length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      attrs = %{email: long_email, name: "Test User"}
      changeset = User.changeset(%User{}, attrs)

      refute changeset.valid?
      assert "should be at most 160 character(s)" in errors_on_changeset(changeset).email
    end

    test "accepts all optional fields" do
      attrs = %{
        email: "test@example.com",
        name: "Test User",
        avatar_url: "https://example.com/avatar.jpg",
        google_uid: "google123",
        google_access_token: "token123",
        gmail_connected_at: DateTime.utc_now(),
        historical_email_sync_completed: true
      }

      changeset = User.changeset(%User{}, attrs)
      assert changeset.valid?
    end
  end

  describe "google_oauth_changeset/2" do
    test "valid Google OAuth changeset" do
      user = %User{}
      attrs = %{
        google_uid: "google123",
        google_access_token: "access_token",
        google_refresh_token: "refresh_token",
        google_token_expires_at: DateTime.utc_now(),
        gmail_connected_at: DateTime.utc_now()
      }

      changeset = User.google_oauth_changeset(user, attrs)
      assert changeset.valid?
    end

    test "requires google_uid" do
      user = %User{}
      attrs = %{google_access_token: "access_token"}

      changeset = User.google_oauth_changeset(user, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on_changeset(changeset).google_uid
    end

    test "requires google_access_token" do
      user = %User{}
      attrs = %{google_uid: "google123"}

      changeset = User.google_oauth_changeset(user, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on_changeset(changeset).google_access_token
    end
  end

  describe "hubspot_oauth_changeset/2" do
    test "valid HubSpot OAuth changeset" do
      user = %User{}
      attrs = %{
        hubspot_access_token: "hubspot_token",
        hubspot_refresh_token: "refresh_token",
        hubspot_token_expires_at: DateTime.utc_now(),
        hubspot_connected_at: DateTime.utc_now()
      }

      changeset = User.hubspot_oauth_changeset(user, attrs)
      assert changeset.valid?
    end

    test "requires hubspot_access_token" do
      user = %User{}
      attrs = %{hubspot_refresh_token: "refresh_token"}

      changeset = User.hubspot_oauth_changeset(user, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on_changeset(changeset).hubspot_access_token
    end

    test "accepts optional fields" do
      user = %User{}
      attrs = %{
        hubspot_access_token: "token123",
        hubspot_connected_at: DateTime.utc_now()
      }

      changeset = User.hubspot_oauth_changeset(user, attrs)
      assert changeset.valid?
    end
  end

  defp errors_on_changeset(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

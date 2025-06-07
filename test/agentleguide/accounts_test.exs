defmodule Agentleguide.AccountsTest do
  use Agentleguide.DataCase

  alias Agentleguide.Accounts
  alias Agentleguide.Accounts.User

  describe "users" do
    @valid_attrs %{
      email: "test@example.com",
      name: "Test User",
      avatar_url: "https://example.com/avatar.jpg"
    }

    @google_oauth_attrs %{
      email: "test@example.com",
      name: "Test User",
      avatar_url: "https://example.com/avatar.jpg",
      google_uid: "123456789",
      google_access_token: "test_access_token",
      google_refresh_token: "test_refresh_token",
      google_token_expires_at: ~U[2024-01-01 00:00:00Z]
    }

    def user_fixture(attrs \\ %{}) do
      {:ok, user} =
        attrs
        |> Enum.into(@valid_attrs)
        |> then(&(%User{} |> User.changeset(&1) |> Agentleguide.Repo.insert()))

      user
    end

    def google_user_fixture(attrs \\ %{}) do
      {:ok, user} =
        attrs
        |> Enum.into(@google_oauth_attrs)
        |> then(&(%User{} |> User.changeset(&1) |> Agentleguide.Repo.insert()))

      user
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Accounts.get_user!(user.id) == user
    end

    test "get_user_by_email/1 returns the user with given email" do
      user = user_fixture()
      assert Accounts.get_user_by_email(user.email) == user
    end

    test "get_user_by_email/1 returns nil for non-existent email" do
      assert Accounts.get_user_by_email("nonexistent@example.com") == nil
    end

    test "get_user_by_google_uid/1 returns the user with given google_uid" do
      user = google_user_fixture()
      assert Accounts.get_user_by_google_uid(user.google_uid) == user
    end

    test "get_user_by_google_uid/1 returns nil for non-existent google_uid" do
      assert Accounts.get_user_by_google_uid("nonexistent") == nil
    end
  end

  describe "Google OAuth integration" do
    def mock_google_auth(overrides \\ %{}) do
      %Ueberauth.Auth{
        uid: "123456789",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "access_token_123",
          refresh_token: "refresh_token_123",
          # 2022-01-01 00:00:00 UTC
          expires_at: 1_640_995_200
        }
      }
      |> Map.merge(overrides)
    end

    test "create_user_from_google/1 creates a new user from Google OAuth data" do
      auth = mock_google_auth()

      assert {:ok, user} = Accounts.create_user_from_google(auth)
      assert user.email == "test@example.com"
      assert user.name == "Test User"
      assert user.avatar_url == "https://example.com/avatar.jpg"
      assert user.google_uid == "123456789"
      assert user.google_access_token == "access_token_123"
      assert user.google_refresh_token == "refresh_token_123"
      assert user.gmail_connected_at != nil
      assert user.calendar_connected_at != nil
    end

    test "create_user_from_google/1 handles auth without expires_at" do
      auth =
        mock_google_auth(%{
          credentials: %Ueberauth.Auth.Credentials{
            token: "access_token_123",
            refresh_token: "refresh_token_123",
            expires_at: nil
          }
        })

      assert {:ok, user} = Accounts.create_user_from_google(auth)
      assert user.google_token_expires_at == nil
    end

    test "update_user_google_tokens/2 updates existing user tokens" do
      user = google_user_fixture()

      auth =
        mock_google_auth(%{
          credentials: %Ueberauth.Auth.Credentials{
            token: "new_access_token",
            refresh_token: "new_refresh_token",
            expires_at: 1_640_995_200
          }
        })

      assert {:ok, updated_user} = Accounts.update_user_google_tokens(user, auth)
      assert updated_user.google_access_token == "new_access_token"
      assert updated_user.google_refresh_token == "new_refresh_token"
      assert updated_user.gmail_connected_at != user.gmail_connected_at
      assert updated_user.calendar_connected_at != user.calendar_connected_at
    end

    test "update_user_google_tokens/2 preserves refresh_token if not provided" do
      user = google_user_fixture(%{google_refresh_token: "original_refresh_token"})

      auth =
        mock_google_auth(%{
          credentials: %Ueberauth.Auth.Credentials{
            token: "new_access_token",
            refresh_token: nil,
            expires_at: 1_640_995_200
          }
        })

      assert {:ok, updated_user} = Accounts.update_user_google_tokens(user, auth)
      assert updated_user.google_access_token == "new_access_token"
      assert updated_user.google_refresh_token == "original_refresh_token"
    end

    test "find_or_create_user_from_google/1 updates existing user by google_uid" do
      user = google_user_fixture()

      auth =
        mock_google_auth(%{
          uid: user.google_uid,
          credentials: %Ueberauth.Auth.Credentials{
            token: "updated_access_token",
            refresh_token: "updated_refresh_token",
            expires_at: 1_640_995_200
          }
        })

      assert {:ok, updated_user} = Accounts.find_or_create_user_from_google(auth)
      assert updated_user.id == user.id
      assert updated_user.google_access_token == "updated_access_token"
    end

    test "find_or_create_user_from_google/1 links existing user by email" do
      user = user_fixture(%{email: "test@example.com"})

      auth =
        mock_google_auth(%{
          uid: "new_google_uid",
          info: %Ueberauth.Auth.Info{
            email: "test@example.com",
            name: "Test User",
            image: "https://example.com/avatar.jpg"
          }
        })

      assert {:ok, updated_user} = Accounts.find_or_create_user_from_google(auth)
      assert updated_user.id == user.id
      assert updated_user.google_uid == "new_google_uid"
      assert updated_user.google_access_token == "access_token_123"
    end

    test "find_or_create_user_from_google/1 creates new user if none exists" do
      auth = mock_google_auth()

      assert {:ok, user} = Accounts.find_or_create_user_from_google(auth)
      assert user.email == "test@example.com"
      assert user.google_uid == "123456789"
      assert user.google_access_token == "access_token_123"
    end
  end
end

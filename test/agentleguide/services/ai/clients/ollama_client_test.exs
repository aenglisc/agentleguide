defmodule Agentleguide.Services.Ai.Clients.OllamaClientTest do
  use Agentleguide.DataCase, async: false

  @moduletag :skip

  import ExUnit.CaptureLog

  alias Agentleguide.Services.Ai.Clients.OllamaClient
  alias Agentleguide.Accounts

  setup do
    # Create a user for tool execution tests
    {:ok, user} =
      Accounts.create_user_from_google(%Ueberauth.Auth{
        uid: "test_uid",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "google_access_token",
          refresh_token: "google_refresh_token"
        }
      })

    %{user: user}
  end

  describe "generate_embeddings/1" do
    test "handles connection failure" do
      capture_log(fn ->
        assert {:error, "Failed to connect to Ollama. Is it running?"} = OllamaClient.generate_embeddings("test text")
      end)
    end
  end

  describe "chat_completion/2" do
    test "handles basic chat completion", %{user: user} do
      messages = [
        %{"role" => "user", "content" => "Hello, how are you?"}
      ]

      capture_log(fn ->
        assert {:error, "Failed to connect to Ollama. Is it running?"} =
          OllamaClient.chat_completion(messages, user: user)
      end)
    end
  end
end

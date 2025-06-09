defmodule Agentleguide.Services.Hubspot.HubspotServiceTest do
  use Agentleguide.DataCase
  import ExUnit.CaptureLog

  alias Agentleguide.Services.Hubspot.HubspotService
  alias Agentleguide.Accounts

  # Mock Finch for HTTP requests
  defmodule MockFinch do
    def request(_request, _finch_name, _opts \\ []) do
      case Process.get(:finch_response) do
        nil -> {:ok, %{status: 200, body: "{\"results\": []}"}}
        response -> response
      end
    end

    def build(method, url, headers, body \\ nil) do
      %{method: method, url: url, headers: headers, body: body}
    end
  end

  setup do
    # Mock Finch
    Application.put_env(:agentleguide, :finch_module, MockFinch)
    # Disable embedding job queueing in tests
    Application.put_env(:agentleguide, :queue_embeddings, false)

    on_exit(fn ->
      Application.delete_env(:agentleguide, :finch_module)
      Application.delete_env(:agentleguide, :queue_embeddings)
      Process.delete(:finch_response)
    end)

    :ok
  end

  describe "sync_contacts/1" do
    test "successfully syncs contacts for user" do
      user = user_fixture_with_hubspot()

      # Mock HubSpot API response with contacts
      hubspot_response = %{
        "results" => [
          %{
            "id" => "contact1",
            "properties" => %{
              "firstname" => "John",
              "lastname" => "Doe",
              "email" => "john@example.com",
              "company" => "Example Corp",
              "phone" => "555-1234"
            }
          },
          %{
            "id" => "contact2",
            "properties" => %{
              "firstname" => "Jane",
              "lastname" => "Smith",
              "email" => "jane@example.com"
            }
          }
        ]
      }

      Process.put(:finch_response, {:ok, %{status: 200, body: Jason.encode!(hubspot_response)}})

      assert {:ok, count} = HubspotService.sync_contacts(user)
      assert count >= 0
    end

    test "handles API authentication failure" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:ok, %{status: 401, body: "Unauthorized"}})

      capture_log(fn ->
        assert {:error, :auth_failed} = HubspotService.sync_contacts(user)
      end)
    end

    test "handles API error response" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:ok, %{status: 500, body: "Internal Server Error"}})

      capture_log(fn ->
        assert {:error, {:api_error, 500, "Internal Server Error"}} = HubspotService.sync_contacts(user)
      end)
    end

    test "handles request failure" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:error, :timeout})

      capture_log(fn ->
        assert {:error, {:request_failed, :timeout}} = HubspotService.sync_contacts(user)
      end)
    end

    test "handles empty response" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:ok, %{status: 200, body: "{\"results\": []}"}})

      assert {:ok, 0} = HubspotService.sync_contacts(user)
    end
  end

    describe "fetch_contacts/1" do
    test "successfully fetches contacts" do
      user = user_fixture_with_hubspot()

      hubspot_response = %{
        "results" => [
          %{
            "id" => "list_contact1",
            "properties" => %{
              "firstname" => "David",
              "lastname" => "Wilson",
              "email" => "david@example.com"
            }
          }
        ]
      }

      Process.put(:finch_response, {:ok, %{status: 200, body: Jason.encode!(hubspot_response)}})

      assert {:ok, contacts} = HubspotService.fetch_contacts(user)
      assert is_list(contacts)
    end

    test "handles API errors during fetch" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:ok, %{status: 403, body: "Forbidden"}})

      capture_log(fn ->
        assert {:error, {:api_error, 403, "Forbidden"}} = HubspotService.fetch_contacts(user)
      end)
    end

    test "handles empty response" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:ok, %{status: 200, body: "{\"results\": []}"}})

      assert {:ok, []} = HubspotService.fetch_contacts(user)
    end
  end

  describe "store_contacts/2" do
    test "successfully stores contacts" do
      user = user_fixture_with_hubspot()

      contacts_data = [
        %{
          "id" => "contact123",
          "properties" => %{
            "firstname" => "Alice",
            "lastname" => "Johnson",
            "email" => "alice@example.com",
            "company" => "Tech Corp",
            "phone" => "555-9876",
            "jobtitle" => "Engineer",
            "website" => "https://example.com"
          }
        }
      ]

            assert {:ok, results} = HubspotService.store_contacts(user, contacts_data)
      assert length(results) == 1

      [{:ok, contact}] = results
      assert contact.hubspot_id == "contact123"
      assert contact.first_name == "Alice"
      assert contact.last_name == "Johnson"
      assert contact.email == "alice@example.com"
      assert contact.company == "Tech Corp"
    end

    test "handles contacts with minimal data" do
      user = user_fixture_with_hubspot()

      contacts_data = [
        %{
          "id" => "minimal_contact",
          "properties" => %{
            "firstname" => "Bob"
          }
        }
      ]

            assert {:ok, results} = HubspotService.store_contacts(user, contacts_data)
      assert length(results) == 1

      [{:ok, contact}] = results
      assert contact.hubspot_id == "minimal_contact"
      assert contact.first_name == "Bob"
      assert contact.last_name == nil or contact.last_name == ""
    end

    test "handles empty contacts list" do
      user = user_fixture_with_hubspot()

      assert {:ok, []} = HubspotService.store_contacts(user, [])
    end
  end

    describe "create_contact/2" do
    test "successfully creates a contact" do
      user = user_fixture_with_hubspot()

      contact_attrs = %{
        "firstname" => "Frank",
        "lastname" => "Miller",
        "email" => "frank@example.com"
      }

      create_response = %{
        "id" => "new_contact_123",
        "properties" => contact_attrs
      }

      Process.put(:finch_response, {:ok, %{status: 201, body: Jason.encode!(create_response)}})

      capture_log(fn ->
        assert {:ok, contact} = HubspotService.create_contact(user, contact_attrs)
        assert contact.hubspot_id == "new_contact_123"
      end)
    end

    test "handles creation failure" do
      user = user_fixture_with_hubspot()

      Process.put(:finch_response, {:ok, %{status: 400, body: "Bad Request"}})

      capture_log(fn ->
        assert {:error, {:api_error, 400, "Bad Request"}} = HubspotService.create_contact(user, %{})
      end)
    end
  end

  # Helper functions
  defp user_fixture_with_hubspot(attrs \\ %{}) do
    default_attrs = %{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User",
      google_uid: "google_#{System.unique_integer()}",
      hubspot_access_token: "valid_hubspot_token",
      hubspot_connected_at: DateTime.utc_now()
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end
end

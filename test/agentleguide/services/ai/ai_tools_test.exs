defmodule Agentleguide.Services.Ai.AiToolsTest do
  use Agentleguide.DataCase

  alias Agentleguide.{Accounts, Rag}
  alias Agentleguide.Services.Ai.AiTools

  describe "get_available_tools/0" do
    test "returns a list of available tools" do
      tools = AiTools.get_available_tools()

      assert is_list(tools)
      assert length(tools) > 0

      # Check that each tool has the required structure
      Enum.each(tools, fn tool ->
        assert %{"type" => "function", "function" => function} = tool
        assert Map.has_key?(function, "name")
        assert Map.has_key?(function, "description")
        assert Map.has_key?(function, "parameters")
      end)
    end

    test "includes expected tools" do
      tools = AiTools.get_available_tools()
      tool_names = Enum.map(tools, fn tool -> tool["function"]["name"] end)

      expected_tools = [
        "search_contacts",
        "send_email",
        "get_available_time_slots",
        "schedule_meeting",
        "create_hubspot_contact",
        "get_upcoming_events"
      ]

      Enum.each(expected_tools, fn tool_name ->
        assert tool_name in tool_names
      end)
    end
  end

  describe "execute_tool_call/3" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User",
          google_access_token: "fake_token",
          gmail_connected_at: DateTime.utc_now()
        })

      %{user: user}
    end

    test "search_contacts returns formatted contacts", %{user: user} do
      # Create some test contacts
      {:ok, _contact1} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "123",
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com",
          company: "Acme Corp"
        })

      {:ok, _contact2} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "124",
          first_name: "Jane",
          last_name: "Smith",
          email: "jane@example.com",
          company: "Tech Inc"
        })

      result = AiTools.execute_tool_call(user, "search_contacts", %{"query" => "John"})

      assert {:ok, %{"contacts" => contacts, "count" => count}} = result
      assert count > 0
      assert is_list(contacts)

      # Check that John Doe is in the results
      john_contact =
        Enum.find(contacts, fn contact ->
          String.contains?(contact["name"], "John")
        end)

      assert john_contact
      assert john_contact["email"] == "john@example.com"
    end

    test "returns error for unknown tool", %{user: user} do
      result = AiTools.execute_tool_call(user, "unknown_tool", %{})
      assert {:error, "Unknown tool: unknown_tool"} = result
    end

    test "search_contacts with no matches returns empty list", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "search_contacts", %{"query" => "NonexistentPerson"})

      assert {:ok, %{"contacts" => [], "count" => 0}} = result
    end
  end
end

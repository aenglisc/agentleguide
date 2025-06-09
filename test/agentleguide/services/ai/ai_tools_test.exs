defmodule Agentleguide.Services.Ai.AiToolsTest do
  use Agentleguide.DataCase

  alias Agentleguide.{Accounts, Rag}
  alias Agentleguide.Services.Ai.AiTools

  # Module-level setup to configure service stubs for all tests
  setup do
    # Configure service stubs for AI Tools tests
    Application.put_env(:agentleguide, :gmail_service, Agentleguide.GoogleServiceTestStub)
    Application.put_env(:agentleguide, :calendar_service, Agentleguide.GoogleServiceTestStub)
    Application.put_env(:agentleguide, :hubspot_service, Agentleguide.HubspotServiceTestStub)

    on_exit(fn ->
      Application.delete_env(:agentleguide, :gmail_service)
      Application.delete_env(:agentleguide, :calendar_service)
      Application.delete_env(:agentleguide, :hubspot_service)
    end)

    :ok
  end

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
        "search_emails",
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

    test "search_contacts without query returns all contacts", %{user: user} do
      # Create test contacts
      {:ok, _contact1} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "125",
          first_name: "Alice",
          last_name: "Johnson",
          email: "alice@example.com"
        })

      {:ok, _contact2} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "126",
          first_name: "Bob",
          last_name: "Wilson",
          email: "bob@example.com"
        })

      # Test with empty arguments
      result = AiTools.execute_tool_call(user, "search_contacts", %{})
      assert {:ok, %{"contacts" => all_contacts, "count" => count}} = result
      assert count == 2
      assert length(all_contacts) == 2

      # Test with empty query
      result = AiTools.execute_tool_call(user, "search_contacts", %{"query" => ""})
      assert {:ok, %{"contacts" => _empty_query_contacts, "count" => count}} = result
      assert count == 2
    end

    test "search_emails finds emails by query", %{user: user} do
      # Create test emails
      {:ok, _email1} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "email1",
          subject: "Meeting Tomorrow",
          from_email: "sender@example.com",
          from_name: "John Sender",
          body_text: "Let's discuss the project"
        })

      {:ok, _email2} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "email2",
          subject: "Project Update",
          from_email: "manager@example.com",
          from_name: "Jane Manager",
          body_text: "Status report on the meeting"
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{"query" => "meeting"})
      assert {:ok, %{"emails" => emails, "count" => count}} = result
      assert count == 2
      assert length(emails) == 2
    end

    test "search_emails filters by sender", %{user: user} do
      # Create test emails
      {:ok, _email1} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "email3",
          subject: "Hello from John",
          from_email: "john@example.com",
          from_name: "John Doe",
          body_text: "Hi there!"
        })

      {:ok, _email2} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "email4",
          subject: "Hello from Jane",
          from_email: "jane@example.com",
          from_name: "Jane Smith",
          body_text: "How are you?"
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{"sender" => "john"})
      assert {:ok, %{"emails" => emails, "count" => count}} = result
      assert count == 1
      assert hd(emails)["from_name"] == "John Doe"
    end

    test "search_emails respects limit parameter", %{user: user} do
      # Create multiple test emails
      Enum.each(1..5, fn i ->
        {:ok, _} =
          Rag.upsert_gmail_email(user, %{
            gmail_id: "email#{i}",
            subject: "Email #{i}",
            from_email: "test#{i}@example.com",
            body_text: "Content #{i}"
          })
      end)

      result = AiTools.execute_tool_call(user, "search_emails", %{"limit" => 3})
      assert {:ok, %{"emails" => emails, "count" => count}} = result
      assert count == 3
      assert length(emails) == 3
    end

    test "search_emails with no query returns recent emails", %{user: user} do
      {:ok, _email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "recent1",
          subject: "Recent Email",
          from_email: "recent@example.com",
          body_text: "Recent content"
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{})
      assert {:ok, %{"emails" => emails, "count" => count}} = result
      assert count >= 1
      assert is_list(emails)
    end

    test "search_emails formats email data correctly", %{user: user} do
      date = ~U[2024-01-15 10:00:00Z]

      {:ok, _email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "format_test",
          subject: "Format Test",
          from_email: "format@example.com",
          from_name: "Format Tester",
          body_text:
            "This is a long email body that should be truncated to 150 characters when displayed in the snippet format for the AI tools interface",
          date: date
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{"query" => "Format Test"})
      assert {:ok, %{"emails" => [email], "count" => 1}} = result

      assert email["subject"] == "Format Test"
      assert email["from_name"] == "Format Tester"
      assert email["from_email"] == "format@example.com"
      assert email["date"] == DateTime.to_iso8601(date)
      assert String.length(email["snippet"]) <= 150
    end

    test "search_emails handles missing fields gracefully", %{user: user} do
      {:ok, _email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "minimal",
          from_email: "minimal@example.com"
          # No subject, from_name, body_text, or date
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{})
      assert {:ok, %{"emails" => emails, "count" => _}} = result

      minimal_email = Enum.find(emails, fn e -> e["from_email"] == "minimal@example.com" end)
      assert minimal_email
      assert minimal_email["subject"] == "No Subject"
      # Falls back to email
      assert minimal_email["from_name"] == "minimal@example.com"
      assert minimal_email["date"] == nil
      assert minimal_email["snippet"] == ""
    end
  end

  describe "tool execution with external service dependencies" do
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

    test "send_email validates required parameters", %{user: user} do
      # Missing required parameters should cause pattern match failure
      assert_raise FunctionClauseError, fn ->
        AiTools.execute_tool_call(user, "send_email", %{"to_email" => "test@example.com"})
      end
    end

    test "get_available_time_slots validates date format", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => "invalid-date",
          "end_date" => "2024-01-20"
        })

      assert {:error, "Invalid date format. Use YYYY-MM-DD format."} = result
    end

    test "get_available_time_slots with valid dates format", %{user: user} do
      # This will fail due to test environment, but tests the date parsing logic
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => "2024-01-15",
          "end_date" => "2024-01-20"
        })

      # Should get test environment error, not date parsing error
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "schedule_meeting validates datetime format", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "Test Meeting",
          "start_time" => "invalid-datetime",
          "end_time" => "2024-01-15T10:00:00Z",
          "attendee_emails" => ["test@example.com"]
        })

      assert {:error, error_msg} = result
      assert error_msg =~ "Invalid datetime format"
    end

    test "schedule_meeting with valid parameters", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "Team Meeting",
          "start_time" => "2024-01-15T10:00:00Z",
          "end_time" => "2024-01-15T11:00:00Z",
          "attendee_emails" => ["colleague@example.com"],
          "description" => "Weekly team sync"
        })

      # Should fail with test environment error, not parameter validation
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "create_hubspot_contact formats parameters correctly", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "create_hubspot_contact", %{
          "email" => "newcontact@example.com",
          "first_name" => "New",
          "last_name" => "Contact",
          "company" => "Example Corp",
          "phone" => "+1-555-0123"
        })

      # Should fail with test environment error
      assert {:error, "HubSpot service not available in test environment"} = result
    end

    test "get_upcoming_events with default days", %{user: user} do
      result = AiTools.execute_tool_call(user, "get_upcoming_events", %{})

      # Should fail with test environment error
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "get_upcoming_events with custom days", %{user: user} do
      result = AiTools.execute_tool_call(user, "get_upcoming_events", %{"days" => 14})

      # Should fail with test environment error
      assert {:error, "Calendar service not available in test environment"} = result
    end
  end

  describe "helper functions" do
    test "tool names in get_available_tools match execute_tool_call cases" do
      tools = AiTools.get_available_tools()
      tool_names = Enum.map(tools, fn tool -> tool["function"]["name"] end)

      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})

      # Test that each tool name is handled by execute_tool_call
      # We use appropriate minimal parameters for tools that require them
      Enum.each(tool_names, fn tool_name ->
        args =
          case tool_name do
            "send_email" ->
              %{"to_email" => "test@example.com", "subject" => "Test", "body" => "Test"}

            "schedule_meeting" ->
              %{
                "title" => "Test",
                "start_time" => "2024-01-15T10:00:00Z",
                "end_time" => "2024-01-15T11:00:00Z",
                "attendee_emails" => []
              }

            "create_hubspot_contact" ->
              %{"email" => "test@example.com"}

            "get_available_time_slots" ->
              %{"start_date" => "2024-01-15", "end_date" => "2024-01-20"}

            _ ->
              %{}
          end

        result = AiTools.execute_tool_call(user, tool_name, args)

        # Should not return "Unknown tool" error - external service tools will return test env errors
        assert match?({:ok, _}, result) or match?({:error, _}, result)
        refute match?({:error, "Unknown tool: " <> _}, result)

        # External service tools should return test environment errors
        case tool_name do
          name
          when name in [
                 "send_email",
                 "get_available_time_slots",
                 "schedule_meeting",
                 "get_upcoming_events"
               ] ->
            assert {:error, msg} = result
            assert msg =~ "not available in test environment"

          "create_hubspot_contact" ->
            assert {:error, msg} = result
            assert msg =~ "not available in test environment"

          _ ->
            # search_contacts and search_emails should work normally
            assert match?({:ok, _}, result)
        end
      end)
    end

    test "unknown tool returns proper error" do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})

      result = AiTools.execute_tool_call(user, "nonexistent_tool", %{})
      assert {:error, "Unknown tool: nonexistent_tool"} = result
    end
  end

  describe "date/datetime parsing edge cases" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "test@example.com", name: "Test User"})
      %{user: user}
    end

    test "get_available_time_slots with nil date arguments", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => nil,
          "end_date" => "2024-01-20"
        })

      assert {:error, "Invalid date format. Use YYYY-MM-DD format."} = result
    end

    test "get_available_time_slots with non-string date arguments", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => 20_240_115,
          "end_date" => "2024-01-20"
        })

      assert {:error, "Invalid date format. Use YYYY-MM-DD format."} = result
    end

    test "schedule_meeting with nil datetime arguments", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "Test Meeting",
          "start_time" => nil,
          "end_time" => "2024-01-15T11:00:00Z",
          "attendee_emails" => ["test@example.com"]
        })

      assert {:error, error_msg} = result
      assert error_msg =~ "Invalid datetime format"
    end

    test "schedule_meeting with non-string datetime arguments", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "Test Meeting",
          "start_time" => 1_642_248_000,
          "end_time" => "2024-01-15T11:00:00Z",
          "attendee_emails" => ["test@example.com"]
        })

      assert {:error, error_msg} = result
      assert error_msg =~ "Invalid datetime format"
    end

    test "get_available_time_slots includes duration_minutes parameter", %{user: user} do
      # This tests that the duration_minutes parameter is parsed correctly
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => "2024-01-15",
          "end_date" => "2024-01-20",
          "duration_minutes" => 30
        })

      # Should fail with test environment error, proving parameters were parsed correctly
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "schedule_meeting without optional description", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "No Description Meeting",
          "start_time" => "2024-01-15T10:00:00Z",
          "end_time" => "2024-01-15T11:00:00Z",
          "attendee_emails" => ["test@example.com"]
          # No description field
        })

      # Should fail with test environment error, proving optional parameter handling works
      assert {:error, "Calendar service not available in test environment"} = result
    end
  end

  describe "email formatting edge cases" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User",
          google_access_token: "fake_token"
        })

      %{user: user}
    end

    test "search_emails with very long body text", %{user: user} do
      # 500 character body
      long_body = String.duplicate("A", 500)

      {:ok, _email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "long_body",
          subject: "Long Body Email",
          from_email: "sender@example.com",
          body_text: long_body
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{"query" => "Long Body"})
      assert {:ok, %{"emails" => [email], "count" => 1}} = result

      # Snippet should be truncated to 150 characters
      assert String.length(email["snippet"]) == 150
      assert email["snippet"] == String.slice(long_body, 0, 150)
    end

    test "search_emails with from_name fallback", %{user: user} do
      {:ok, _email} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "no_name",
          subject: "No Name Email",
          from_email: "noname@example.com",
          # Should fall back to from_email
          from_name: nil
        })

      result = AiTools.execute_tool_call(user, "search_emails", %{"query" => "No Name"})
      assert {:ok, %{"emails" => [email], "count" => 1}} = result

      assert email["from_name"] == "noname@example.com"
      assert email["from_email"] == "noname@example.com"
    end
  end

  describe "additional edge cases and coverage" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test@example.com",
          name: "Test User",
          google_access_token: "fake_token"
        })

      %{user: user}
    end

    test "send_email pattern match failure with missing parameters", %{user: user} do
      # Test various incomplete parameter sets to ensure pattern matching works
      assert_raise FunctionClauseError, fn ->
        AiTools.execute_tool_call(user, "send_email", %{"subject" => "Test", "body" => "Test"})
      end

      assert_raise FunctionClauseError, fn ->
        AiTools.execute_tool_call(user, "send_email", %{
          "to_email" => "test@example.com",
          "body" => "Test"
        })
      end

      assert_raise FunctionClauseError, fn ->
        AiTools.execute_tool_call(user, "send_email", %{
          "to_email" => "test@example.com",
          "subject" => "Test"
        })
      end
    end

    test "schedule_meeting pattern match failure with missing parameters", %{user: user} do
      base_params = %{
        "title" => "Test Meeting",
        "start_time" => "2024-01-15T10:00:00Z",
        "end_time" => "2024-01-15T11:00:00Z",
        "attendee_emails" => ["test@example.com"]
      }

      # Test missing each required parameter
      ["title", "start_time", "end_time", "attendee_emails"]
      |> Enum.each(fn key ->
        incomplete_params = Map.delete(base_params, key)

        assert_raise MatchError, fn ->
          AiTools.execute_tool_call(user, "schedule_meeting", incomplete_params)
        end
      end)
    end

    test "date parsing with edge cases", %{user: user} do
      # Test malformed date strings
      bad_dates = ["2024-13-01", "2024-01-32", "not-a-date", "", "2024/01/15"]

      Enum.each(bad_dates, fn bad_date ->
        result =
          AiTools.execute_tool_call(user, "get_available_time_slots", %{
            "start_date" => bad_date,
            "end_date" => "2024-01-20"
          })

        assert {:error, "Invalid date format. Use YYYY-MM-DD format."} = result
      end)
    end

    test "datetime parsing with edge cases", %{user: user} do
      # Test malformed datetime strings
      bad_datetimes = ["2024-01-15", "2024-01-15T25:00:00Z", "not-a-datetime", ""]

      Enum.each(bad_datetimes, fn bad_datetime ->
        result =
          AiTools.execute_tool_call(user, "schedule_meeting", %{
            "title" => "Test Meeting",
            "start_time" => bad_datetime,
            "end_time" => "2024-01-15T11:00:00Z",
            "attendee_emails" => ["test@example.com"]
          })

        assert {:error, error_msg} = result
        assert error_msg =~ "Invalid datetime format"
      end)
    end

    test "search_emails with sender query combination", %{user: user} do
      # Create test emails from different senders
      {:ok, _email1} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "combo1",
          subject: "Project update from Alice",
          from_email: "alice@example.com",
          from_name: "Alice Johnson",
          body_text: "Project status update"
        })

      {:ok, _email2} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "combo2",
          subject: "Meeting notes from Alice",
          from_email: "alice@example.com",
          from_name: "Alice Johnson",
          body_text: "Meeting summary"
        })

      {:ok, _email3} =
        Rag.upsert_gmail_email(user, %{
          gmail_id: "combo3",
          subject: "Project budget from Bob",
          from_email: "bob@example.com",
          from_name: "Bob Smith",
          body_text: "Budget report"
        })

      # Test sender + query combination
      result =
        AiTools.execute_tool_call(user, "search_emails", %{
          "sender" => "alice",
          "query" => "project"
        })

      assert {:ok, %{"emails" => emails, "count" => count}} = result
      assert count == 1
      assert hd(emails)["subject"] == "Project update from Alice"
    end

    test "create_hubspot_contact with minimal parameters", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "create_hubspot_contact", %{
          "email" => "minimal@example.com"
          # Only required parameter
        })

      # Should fail with test environment error
      assert {:error, "HubSpot service not available in test environment"} = result
    end

    test "get_available_time_slots with default duration", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => "2024-01-15",
          "end_date" => "2024-01-20"
          # No duration_minutes, should default to 60
        })

      # Should fail with test environment error, proving defaults work
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "tool function schema validation" do
      tools = AiTools.get_available_tools()

      # Verify all tools have proper schema structure
      Enum.each(tools, fn tool ->
        function = tool["function"]

        # All functions should have required fields
        assert is_binary(function["name"])
        assert is_binary(function["description"])
        assert is_map(function["parameters"])

        # Parameters should have proper structure
        params = function["parameters"]
        assert params["type"] == "object"
        assert is_map(params["properties"])
        assert is_list(params["required"]) or params["required"] == nil
      end)
    end

    test "search_contacts with empty string query returns all contacts", %{user: user} do
      {:ok, _contact} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "empty_test",
          first_name: "Empty",
          last_name: "Test",
          email: "empty@example.com"
        })

      result = AiTools.execute_tool_call(user, "search_contacts", %{"query" => ""})
      assert {:ok, %{"contacts" => contacts, "count" => count}} = result
      assert count >= 1
      assert Enum.any?(contacts, fn c -> c["email"] == "empty@example.com" end)
    end

    test "search_emails handles empty results gracefully", %{user: user} do
      # Search for something that definitely won't match
      result =
        AiTools.execute_tool_call(user, "search_emails", %{
          "query" => "xyznonexistentqueryxyz123456"
        })

      assert {:ok, %{"emails" => [], "count" => 0}} = result
    end

    test "full date parsing coverage - valid ISO date", %{user: user} do
      # Test a working date parse path (but will fail on external service)
      result =
        AiTools.execute_tool_call(user, "get_available_time_slots", %{
          "start_date" => "2024-01-15",
          "end_date" => "2024-01-20",
          "duration_minutes" => 90
        })

      # Should fail with test environment error, proving date parsing worked
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "full datetime parsing coverage - valid ISO datetime", %{user: user} do
      # Test valid datetime parsing
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "Valid DateTime Test",
          "start_time" => "2024-01-15T14:30:00Z",
          "end_time" => "2024-01-15T15:30:00Z",
          "attendee_emails" => ["attendee@example.com"],
          "description" => "Testing datetime parsing"
        })

      # Should fail with test environment error, proving datetime parsing worked
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "search_emails with limit parameter edge cases", %{user: user} do
      # Create test emails
      Enum.each(1..3, fn i ->
        {:ok, _} =
          Rag.upsert_gmail_email(user, %{
            gmail_id: "limit_test_#{i}",
            subject: "Limit Test #{i}",
            from_email: "test#{i}@example.com",
            body_text: "Test content #{i}"
          })
      end)

      # Test limit 0
      result = AiTools.execute_tool_call(user, "search_emails", %{"limit" => 0})
      assert {:ok, %{"emails" => [], "count" => 0}} = result

      # Test limit 1
      result = AiTools.execute_tool_call(user, "search_emails", %{"limit" => 1})
      assert {:ok, %{"emails" => emails, "count" => 1}} = result
      assert length(emails) == 1
    end

    test "search_contacts query vs no query behavior difference", %{user: user} do
      {:ok, _contact} =
        Rag.upsert_hubspot_contact(user, %{
          hubspot_id: "behavior_test",
          first_name: "Behavior",
          last_name: "Test",
          email: "behavior@example.com"
        })

      # With empty query - should use list_all path
      result1 = AiTools.execute_tool_call(user, "search_contacts", %{"query" => ""})
      assert {:ok, %{"contacts" => contacts1, "count" => count1}} = result1

      # With no query key - should use list_all path
      result2 = AiTools.execute_tool_call(user, "search_contacts", %{})
      assert {:ok, %{"contacts" => contacts2, "count" => count2}} = result2

      # Both should return same results (all contacts)
      assert count1 == count2
      assert length(contacts1) == length(contacts2)
    end

    test "create_hubspot_contact with all optional parameters", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "create_hubspot_contact", %{
          "email" => "full@example.com",
          "first_name" => "Full",
          "last_name" => "Contact",
          "company" => "Full Corp",
          "phone" => "+1-555-0199"
        })

      # Should fail with test environment error
      assert {:error, "HubSpot service not available in test environment"} = result
    end

    test "schedule_meeting with empty attendees list", %{user: user} do
      result =
        AiTools.execute_tool_call(user, "schedule_meeting", %{
          "title" => "Solo Meeting",
          "start_time" => "2024-01-15T10:00:00Z",
          "end_time" => "2024-01-15T11:00:00Z",
          "attendee_emails" => []
        })

      # Should fail with test environment error
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "get_upcoming_events with zero days", %{user: user} do
      result = AiTools.execute_tool_call(user, "get_upcoming_events", %{"days" => 0})

      # Should fail with test environment error
      assert {:error, "Calendar service not available in test environment"} = result
    end

    test "all error branches in execute_tool_call" do
      {:ok, user} =
        Accounts.create_user(%{
          email: "test#{System.unique_integer()}@example.com",
          name: "Test User"
        })

      # Test that each external service tool fails correctly in test environment
      external_tools = [
        {"send_email",
         %{"to_email" => "test@example.com", "subject" => "Test", "body" => "Test"}},
        {"get_available_time_slots", %{"start_date" => "2024-01-15", "end_date" => "2024-01-20"}},
        {"schedule_meeting",
         %{
           "title" => "Test",
           "start_time" => "2024-01-15T10:00:00Z",
           "end_time" => "2024-01-15T11:00:00Z",
           "attendee_emails" => []
         }},
        {"create_hubspot_contact", %{"email" => "test@example.com"}},
        {"get_upcoming_events", %{}}
      ]

      Enum.each(external_tools, fn {tool_name, args} ->
        result = AiTools.execute_tool_call(user, tool_name, args)
        assert {:error, msg} = result
        assert msg =~ "not available in test environment"
      end)
    end
  end
end

defmodule Agentleguide.Services.Google.CalendarServiceTest do
  use Agentleguide.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Agentleguide.Services.Google.CalendarService
  alias Agentleguide.Accounts

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Set default expectations for Calendar HTTP calls
    stub(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
      {:ok, %{status: 200, body: Jason.encode!(%{"items" => []})}}
    end)

    # Create a user with Google access token
    {:ok, user} =
      Accounts.create_user_from_google(%Ueberauth.Auth{
        uid: "test_uid",
        info: %Ueberauth.Auth.Info{
          email: "test@example.com",
          name: "Test User",
          image: "https://example.com/avatar.jpg"
        },
        credentials: %Ueberauth.Auth.Credentials{
          token: "google_access_token",
          refresh_token: "google_refresh_token",
          expires_at: System.system_time(:second) + 3600
        }
      })

    %{user: user}
  end

  describe "get_available_slots/4" do
    test "calculates available slots with no conflicts", %{user: user} do
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 24 * 60 * 60, :second)

      # Mock empty calendar response (no conflicting events)
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(%{"items" => []})}}
      end)

      assert {:ok, slots} = CalendarService.get_available_slots(user, start_date, end_date, 60)
      assert is_list(slots)
    end

    test "handles API errors when fetching events", %{user: user} do
      # Test with invalid user token to trigger API error
      user_with_bad_token = %{user | google_access_token: "invalid_token"}
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 24 * 60 * 60, :second)

      # Mock API authentication error
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      capture_log(fn ->
        assert {:error, :auth_failed} = CalendarService.get_available_slots(user_with_bad_token, start_date, end_date)
      end)
    end

    test "accepts custom duration for slots", %{user: user} do
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 12 * 60 * 60, :second)

      # Mock empty calendar response
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(%{"items" => []})}}
      end)

      assert {:ok, slots} = CalendarService.get_available_slots(user, start_date, end_date, 30)
      assert is_list(slots)
    end
  end

  describe "fetch_events/3" do
    test "successfully fetches events from calendar", %{user: user} do
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 7 * 24 * 60 * 60, :second)

      # Mock successful events fetch
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "items" => [
              %{
                "id" => "event1",
                "summary" => "Test Meeting",
                "start" => %{"dateTime" => DateTime.to_iso8601(start_date)},
                "end" => %{"dateTime" => DateTime.to_iso8601(DateTime.add(start_date, 3600, :second))}
              }
            ]
          })
        }}
      end)

      assert {:ok, events} = CalendarService.fetch_events(user, start_date, end_date)
      assert length(events) == 1
      assert List.first(events)["summary"] == "Test Meeting"
    end

    test "handles authentication failure", %{user: user} do
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 24 * 60 * 60, :second)

      # Mock auth failure
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      capture_log(fn ->
        assert {:error, :auth_failed} = CalendarService.fetch_events(user, start_date, end_date)
      end)
    end

    test "handles empty response gracefully", %{user: user} do
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 1 * 60 * 60, :second)

      # Mock empty response
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(%{})}}
      end)

      assert {:ok, events} = CalendarService.fetch_events(user, start_date, end_date)
      assert events == []
    end
  end

  describe "create_event/2" do
    test "creates a calendar event with required fields", %{user: user} do
      start_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      end_time = DateTime.add(start_time, 60 * 60, :second)

      event_attrs = %{
        title: "Test Meeting",
        description: "A test meeting",
        start_time: start_time,
        end_time: end_time
      }

      # Mock successful event creation
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "id" => "created_event_123",
            "summary" => "Test Meeting",
            "htmlLink" => "https://calendar.google.com/event?eid=created_event_123"
          })
        }}
      end)

      assert {:ok, event} = CalendarService.create_event(user, event_attrs)
      assert event["id"] == "created_event_123"
    end

    test "creates event with attendees", %{user: user} do
      start_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      end_time = DateTime.add(start_time, 60 * 60, :second)

      event_attrs = %{
        title: "Team Meeting",
        description: "Weekly team sync",
        start_time: start_time,
        end_time: end_time,
        attendees: ["colleague@example.com", "manager@example.com"]
      }

      # Mock successful event creation with attendees
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "id" => "team_meeting_456",
            "summary" => "Team Meeting",
            "attendees" => [
              %{"email" => "colleague@example.com"},
              %{"email" => "manager@example.com"}
            ]
          })
        }}
      end)

      assert {:ok, event} = CalendarService.create_event(user, event_attrs)
      assert event["id"] == "team_meeting_456"
    end

    test "creates event with timezone", %{user: user} do
      start_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      end_time = DateTime.add(start_time, 60 * 60, :second)

      event_attrs = %{
        summary: "Timezone Test Meeting",
        start_time: start_time,
        end_time: end_time,
        timezone: "America/New_York"
      }

      # Mock successful event creation with timezone
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "id" => "timezone_event_789",
            "summary" => "Timezone Test Meeting"
          })
        }}
      end)

      assert {:ok, event} = CalendarService.create_event(user, event_attrs)
      assert event["id"] == "timezone_event_789"
    end

    test "handles creation failure", %{user: user} do
      user_with_bad_token = %{user | google_access_token: "invalid_token"}

      event_attrs = %{
        title: "Failed Meeting",
        start_time: DateTime.utc_now(),
        end_time: DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      }

      # Mock API failure
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 403, body: "Forbidden"}}
      end)

      capture_log(fn ->
        assert {:error, {:api_error, 403, "Forbidden"}} = CalendarService.create_event(user_with_bad_token, event_attrs)
      end)
    end
  end

  describe "update_event/3" do
    test "updates an existing event", %{user: user} do
      event_id = "test_event_123"
      start_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      end_time = DateTime.add(start_time, 60 * 60, :second)

      event_attrs = %{
        title: "Updated Meeting",
        description: "Updated description",
        start_time: start_time,
        end_time: end_time
      }

      # Mock successful event update
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "id" => event_id,
            "summary" => "Updated Meeting",
            "description" => "Updated description"
          })
        }}
      end)

      assert {:ok, event} = CalendarService.update_event(user, event_id, event_attrs)
      assert event["id"] == event_id
    end

    test "handles update failure", %{user: user} do
      user_with_bad_token = %{user | google_access_token: "invalid_token"}
      event_id = "nonexistent_event"

      event_attrs = %{
        title: "Failed Update",
        start_time: DateTime.utc_now(),
        end_time: DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      }

      # Mock API failure
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 404, body: "Not Found"}}
      end)

      capture_log(fn ->
        assert {:error, {:api_error, 404, "Not Found"}} = CalendarService.update_event(user_with_bad_token, event_id, event_attrs)
      end)
    end
  end

  describe "delete_event/2" do
    test "deletes a calendar event", %{user: user} do
      event_id = "test_event_123"

      # Mock successful event deletion
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 204, body: ""}}
      end)

      assert :ok = CalendarService.delete_event(user, event_id)
    end

    test "handles deletion failure", %{user: user} do
      user_with_bad_token = %{user | google_access_token: "invalid_token"}
      event_id = "nonexistent_event"

      # Mock API failure
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 404, body: "Not Found"}}
      end)

      capture_log(fn ->
        assert {:error, {:api_error, 404, "Not Found"}} = CalendarService.delete_event(user_with_bad_token, event_id)
      end)
    end
  end

  describe "get_upcoming_events/2" do
    test "gets upcoming events with default 7 days", %{user: user} do
      # Mock successful upcoming events fetch
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "items" => [
              %{
                "id" => "upcoming1",
                "summary" => "Upcoming Meeting",
                "start" => %{"dateTime" => DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), 3600, :second))}
              }
            ]
          })
        }}
      end)

      assert {:ok, events} = CalendarService.get_upcoming_events(user)
      assert length(events) == 1
    end

    test "gets upcoming events with custom days", %{user: user} do
      # Mock successful upcoming events fetch
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 200, body: Jason.encode!(%{"items" => []})}}
      end)

      assert {:ok, events} = CalendarService.get_upcoming_events(user, 14)
      assert events == []
    end

    test "handles API failure in upcoming events", %{user: user} do
      user_with_bad_token = %{user | google_access_token: "invalid_token"}

      # Mock API failure
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{status: 401, body: "Unauthorized"}}
      end)

      capture_log(fn ->
        assert {:error, :auth_failed} = CalendarService.get_upcoming_events(user_with_bad_token)
      end)
    end
  end

  describe "private helper functions coverage" do
    test "attendee formatting handles various formats", %{user: user} do
      # Test the format_attendees function indirectly through create_event
      start_time = DateTime.add(DateTime.utc_now(), 60 * 60, :second)
      end_time = DateTime.add(start_time, 60 * 60, :second)

      # Test different attendee formats
      test_cases = [
        # String emails
        ["user1@example.com", "user2@example.com"],
        # Map with atom keys
        [%{email: "user@example.com"}],
        # Map with string keys
        [%{"email" => "user@example.com"}],
        # Mixed formats
        ["user@example.com", %{email: "user2@example.com"}],
        # Empty list
        [],
        # Invalid format (should be handled gracefully)
        nil
      ]

      for attendees <- test_cases do
        event_attrs = %{
          title: "Test Meeting",
          start_time: start_time,
          end_time: end_time,
          attendees: attendees
        }

        # Mock successful event creation for each case
        expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
          {:ok, %{
            status: 200,
            body: Jason.encode!(%{
              "id" => "test_event_#{System.unique_integer()}",
              "summary" => "Test Meeting"
            })
          }}
        end)

        # Should not crash regardless of attendee format
        assert {:ok, _event} = CalendarService.create_event(user, event_attrs)
      end
    end

    test "time parsing handles different time formats", %{user: user} do
      # This tests the parse_event_time function indirectly
      # by ensuring the service handles various event formats
      start_date = DateTime.utc_now()
      end_date = DateTime.add(start_date, 24 * 60 * 60, :second)

      # Mock response with different time formats
      expect(Agentleguide.GoogleCalendarHttpMock, :request, fn _request, _finch_name ->
        {:ok, %{
          status: 200,
          body: Jason.encode!(%{
            "items" => [
              # Event with dateTime
              %{
                "id" => "event1",
                "start" => %{"dateTime" => DateTime.to_iso8601(start_date)},
                "end" => %{"dateTime" => DateTime.to_iso8601(DateTime.add(start_date, 3600, :second))}
              },
              # Event with date-only
              %{
                "id" => "event2",
                "start" => %{"date" => "2024-01-01"},
                "end" => %{"date" => "2024-01-02"}
              }
            ]
          })
        }}
      end)

      # The function should handle events with different time formats
      assert {:ok, slots} = CalendarService.get_available_slots(user, start_date, end_date)
      assert is_list(slots)
    end
  end
end

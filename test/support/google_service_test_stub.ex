defmodule Agentleguide.GoogleServiceTestStub do
  @moduledoc """
  Test stub for Google services (Gmail, Calendar) that provides safe default implementations
  to prevent real API calls during tests.
  """

  # Gmail functions
  def send_email(_user, _to_email, _subject, _body) do
    {:error, :not_implemented_in_tests}
  end

  # Calendar functions
  def get_available_slots(_user, _start_time, _end_time, _duration) do
    {:error, :not_implemented_in_tests}
  end

  def create_event(_user, _event_attrs) do
    {:error, :not_implemented_in_tests}
  end

  def get_upcoming_events(_user, _days) do
    {:error, :not_implemented_in_tests}
  end
end

defmodule Agentleguide.Jobs.HubspotSyncJobTest do
  use Agentleguide.DataCase
  use Oban.Testing, repo: Agentleguide.Repo
  import ExUnit.CaptureLog

  alias Agentleguide.Jobs.HubspotSyncJob
  alias Agentleguide.Accounts

    # Mock the HubspotService
  defmodule MockHubspotService do
    def sync_contacts(_user) do
      Process.put(:sync_contacts_called, true)
      case Process.get(:hubspot_sync_result) do
        nil -> {:ok, 5}
        result -> result
      end
    end
  end

  setup do
    # Swap in the mock service
    Application.put_env(:agentleguide, :hubspot_service, MockHubspotService)

    on_exit(fn ->
      Application.delete_env(:agentleguide, :hubspot_service)
      Process.delete(:hubspot_sync_result)
      Process.delete(:sync_contacts_called)
    end)

    :ok
  end

  describe "perform/1" do
    test "handles missing user gracefully" do
      # Use a valid UUID format that doesn't exist
      fake_uuid = Ecto.UUID.generate()
      job = %Oban.Job{args: %{"user_id" => fake_uuid}}

      capture_log(fn ->
        assert :ok = HubspotSyncJob.perform(job)
      end)
    end

    test "skips sync when user has no HubSpot connection" do
      user = user_fixture(%{hubspot_connected_at: nil})
      job = %Oban.Job{args: %{"user_id" => user.id}}

      assert :ok = HubspotSyncJob.perform(job)

      # Verify that sync_contacts was not called by checking the process dictionary
      # (our mock would set this if called)
      refute Process.get(:sync_contacts_called)
    end

    test "successfully syncs contacts for connected user" do
      user = user_fixture(%{hubspot_connected_at: DateTime.utc_now()})
      job = %Oban.Job{args: %{"user_id" => user.id}}

      Process.put(:hubspot_sync_result, {:ok, 3})

      assert :ok = HubspotSyncJob.perform(job)
    end

    test "handles sync with no new contacts" do
      user = user_fixture(%{hubspot_connected_at: DateTime.utc_now()})
      job = %Oban.Job{args: %{"user_id" => user.id}}

      Process.put(:hubspot_sync_result, {:ok, 0})

      assert :ok = HubspotSyncJob.perform(job)
    end

    test "handles sync failure" do
      user = user_fixture(%{hubspot_connected_at: DateTime.utc_now()})
      job = %Oban.Job{args: %{"user_id" => user.id}}

      Process.put(:hubspot_sync_result, {:error, "API rate limit exceeded"})

      capture_log(fn ->
        assert {:error, "API rate limit exceeded"} = HubspotSyncJob.perform(job)
      end)
    end
  end

  describe "schedule_now/1" do
    test "schedules immediate HubSpot sync job" do
      user = user_fixture()

      assert {:ok, job} = HubspotSyncJob.schedule_now(user.id)
      assert job.args == %{"user_id" => user.id}
      assert job.queue == "sync"
    end
  end

  describe "schedule_recurring/1" do
    test "schedules recurring HubSpot sync job" do
      user = user_fixture()

      assert {:ok, job} = HubspotSyncJob.schedule_recurring(user.id)
      assert job.args == %{"user_id" => user.id}
      assert job.queue == "sync"

      # In test mode, verify the job was created with schedule_in rather than comparing timestamps
      # In inline test mode, jobs are executed immediately so scheduled_at == attempted_at
      assert is_struct(job, Oban.Job)
      assert job.state == "completed"  # Job completed in inline mode
    end
  end

  describe "job uniqueness" do
    test "prevents duplicate jobs within uniqueness period" do
      user = user_fixture()

      # Insert first job
      assert {:ok, job1} = HubspotSyncJob.schedule_now(user.id)

      # Try to insert duplicate job immediately - should be discarded due to uniqueness
      assert {:ok, job2} = HubspotSyncJob.schedule_now(user.id)

      # With uniqueness, the second job should have the same ID as the first (discarded)
      assert job1.id == job2.id
    end
  end

  defp user_fixture(attrs \\ %{}) do
    default_attrs = %{
      email: "test#{System.unique_integer()}@example.com",
      name: "Test User",
      google_uid: "google_#{System.unique_integer()}"
    }

    {:ok, user} = Accounts.create_user(Map.merge(default_attrs, attrs))
    user
  end
end

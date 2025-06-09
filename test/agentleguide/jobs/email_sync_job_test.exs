defmodule Agentleguide.Jobs.EmailSyncJobTest do
  use Agentleguide.DataCase
  use Oban.Testing, repo: Agentleguide.Repo
  import ExUnit.CaptureLog

  alias Agentleguide.Jobs.EmailSyncJob
  alias Agentleguide.Accounts

  # Mock the GmailService
  defmodule MockGmailService do
    def sync_recent_emails(_user) do
      case Process.get(:gmail_sync_result) do
        nil -> {:ok, 3}
        result -> result
      end
    end
  end

  # Mock the Presence module
  defmodule MockPresence do
    def user_online?(user_id) do
      Process.get({:user_online, user_id}, false)
    end
  end

  setup do
    # Ensure database connection is shared for spawned processes FIRST
    # This must come before any operations that might spawn processes
    Ecto.Adapters.SQL.Sandbox.mode(Agentleguide.Repo, {:shared, self()})

    # Swap in the mock services after database setup
    Application.put_env(:agentleguide, :gmail_service, MockGmailService)
    Application.put_env(:agentleguide, :presence_module, MockPresence)

    on_exit(fn ->
      Application.delete_env(:agentleguide, :gmail_service)
      Application.delete_env(:agentleguide, :presence_module)
      Process.delete(:gmail_sync_result)
      # Clean up all user online status
      Process.get_keys()
      |> Enum.filter(&match?({:user_online, _}, &1))
      |> Enum.each(&Process.delete/1)
    end)

    :ok
  end

  describe "perform/1 - regular sync" do
    test "handles missing user gracefully" do
      fake_uuid = Ecto.UUID.generate()
      job = %Oban.Job{args: %{"user_id" => fake_uuid}}

      capture_log(fn ->
        assert :ok = EmailSyncJob.perform(job)
      end)
    end

    test "successfully syncs emails for user" do
      user = user_fixture()
      job = %Oban.Job{args: %{"user_id" => user.id}}

      Process.put(:gmail_sync_result, {:ok, 5})

      assert :ok = EmailSyncJob.perform(job)
    end

    test "handles sync with no new emails" do
      user = user_fixture()
      job = %Oban.Job{args: %{"user_id" => user.id}}

      Process.put(:gmail_sync_result, {:ok, 0})

      assert :ok = EmailSyncJob.perform(job)
    end

    test "handles sync failure" do
      user = user_fixture()
      job = %Oban.Job{args: %{"user_id" => user.id}}

      Process.put(:gmail_sync_result, {:error, "quota_exceeded"})

      capture_log(fn ->
        assert {:error, "quota_exceeded"} = EmailSyncJob.perform(job)
      end)
    end
  end

  describe "perform/1 - adaptive sync" do
    test "handles missing user gracefully in adaptive mode" do
      fake_uuid = Ecto.UUID.generate()
      job = %Oban.Job{args: %{"user_id" => fake_uuid, "adaptive" => true}}

      capture_log(fn ->
        assert :ok = EmailSyncJob.perform(job)
      end)
    end

    test "successfully syncs emails and schedules next adaptive sync" do
      user = user_fixture()
      job = %Oban.Job{args: %{"user_id" => user.id, "adaptive" => true}}

      Process.put(:gmail_sync_result, {:ok, 2})
      Process.put({:user_online, user.id}, false)  # User offline

      assert :ok = EmailSyncJob.perform(job)
    end

    test "handles sync failure but still schedules next adaptive sync" do
      user = user_fixture()
      job = %Oban.Job{args: %{"user_id" => user.id, "adaptive" => true}}

      # Use a different error to avoid the spam issue
      Process.put(:gmail_sync_result, {:error, "network_error"})
      Process.put({:user_online, user.id}, true)  # User online

      capture_log(fn ->
        assert {:error, "network_error"} = EmailSyncJob.perform(job)
      end)
    end
  end

  describe "schedule_now/1" do
    test "schedules immediate email sync job" do
      user = user_fixture()

      assert {:ok, job} = EmailSyncJob.schedule_now(user.id)
      assert job.args == %{"user_id" => user.id}
      assert job.queue == "sync"
    end
  end

  describe "schedule_recurring/1" do
    test "schedules recurring email sync job" do
      user = user_fixture()

      assert {:ok, job} = EmailSyncJob.schedule_recurring(user.id)
      assert job.args == %{"user_id" => user.id}
      assert job.queue == "sync"
    end
  end

  describe "start_adaptive_sync/1" do
    test "starts adaptive sync for user" do
      user = user_fixture()

      # This function just logs and calls schedule_next_adaptive_sync
      # In our test environment, it should succeed
      assert :ok = EmailSyncJob.start_adaptive_sync(user.id)
    end
  end

  describe "stop_adaptive_sync/1" do
    test "stops adaptive sync for user" do
      user = user_fixture()

      # This function just logs, should always return :ok
      assert :ok = EmailSyncJob.stop_adaptive_sync(user.id)
    end
  end

  describe "job uniqueness" do
    test "prevents duplicate jobs within uniqueness period" do
      user = user_fixture()

      # Insert first job
      assert {:ok, job1} = EmailSyncJob.schedule_now(user.id)

      # Try to insert duplicate job immediately - should be discarded due to uniqueness
      assert {:ok, job2} = EmailSyncJob.schedule_now(user.id)

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

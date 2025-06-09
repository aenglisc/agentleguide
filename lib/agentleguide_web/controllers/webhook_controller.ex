defmodule AgentleguideWeb.WebhookController do
  use AgentleguideWeb, :controller
  require Logger

  alias Agentleguide.Accounts
  alias Agentleguide.Services.Ai.AiAgent

  @doc """
  Handle Gmail webhook notifications (push notifications)
  """
  def gmail_webhook(conn, params) do
    Logger.info("Received Gmail webhook: #{inspect(params)}")

    case process_gmail_webhook(params) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        Logger.error("Failed to process Gmail webhook: #{inspect(reason)}")
        json(conn, %{status: "error", message: inspect(reason)})
    end
  end

  @doc """
  Handle Google Calendar webhook notifications
  """
  def calendar_webhook(conn, params) do
    Logger.info("Received Calendar webhook: #{inspect(params)}")

    case process_calendar_webhook(params) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        Logger.error("Failed to process Calendar webhook: #{inspect(reason)}")
        json(conn, %{status: "error", message: inspect(reason)})
    end
  end

  @doc """
  Handle HubSpot webhook notifications
  """
  def hubspot_webhook(conn, params) do
    Logger.info("Received HubSpot webhook: #{inspect(params)}")

    case process_hubspot_webhook(params) do
      {:ok, _result} ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        Logger.error("Failed to process HubSpot webhook: #{inspect(reason)}")
        json(conn, %{status: "error", message: inspect(reason)})
    end
  end

  # Private functions

  defp process_gmail_webhook(%{"message" => %{"data" => data}} = _params) do
    with {:ok, decoded_data} <- decode_webhook_data(data),
         {:ok, user} <- find_user_from_gmail_webhook(decoded_data),
         {:ok, _sync_result} <- trigger_email_sync(user) do
      # Process proactive actions based on new emails
      AiAgent.handle_external_event(user, :new_email, decoded_data)
      {:ok, "processed"}
    else
      error -> error
    end
  end

  defp process_gmail_webhook(_params), do: {:error, "Invalid Gmail webhook format"}

  defp process_calendar_webhook(%{"resourceId" => resource_id} = params) do
    with {:ok, user} <- find_user_from_calendar_webhook(params),
         {:ok, changes} <- fetch_calendar_changes(user, resource_id) do
      # Process proactive actions based on calendar changes
      AiAgent.handle_external_event(user, :calendar_change, changes)
      {:ok, "processed"}
    else
      error -> error
    end
  end

  defp process_calendar_webhook(_params), do: {:error, "Invalid Calendar webhook format"}

  defp process_hubspot_webhook(%{"objectId" => object_id, "eventType" => event_type} = params) do
    with {:ok, user} <- find_user_from_hubspot_webhook(params),
         {:ok, object_data} <- fetch_hubspot_object_data(user, object_id, event_type) do
      # Process proactive actions based on HubSpot changes
      AiAgent.handle_external_event(user, :hubspot_change, %{
        event_type: event_type,
        object_id: object_id,
        object_data: object_data
      })

      {:ok, "processed"}
    else
      error -> error
    end
  end

  defp process_hubspot_webhook(_params), do: {:error, "Invalid HubSpot webhook format"}

  defp decode_webhook_data(data) do
    try do
      decoded = Base.decode64!(data)
      {:ok, Jason.decode!(decoded)}
    rescue
      _ -> {:error, "Failed to decode webhook data"}
    end
  end

  defp find_user_from_gmail_webhook(%{"emailAddress" => email}) do
    case Accounts.get_user_by_email(email) do
      %Agentleguide.Accounts.User{} = user -> {:ok, user}
      nil -> {:error, "User not found for email: #{email}"}
    end
  end

  defp find_user_from_gmail_webhook(_), do: {:error, "No email address in webhook data"}

    defp find_user_from_calendar_webhook(%{"channelToken" => _token}) do
    # For calendar webhooks, we need to store the channel token with user mapping
    # For now, we'll try to find by any connected user - in production,
    # you'd want to store token-to-user mapping when setting up the webhook
    case find_user_with_calendar_connected() do
      %Agentleguide.Accounts.User{} = user -> {:ok, user}
      nil -> {:error, "No user found for calendar webhook"}
    end
  end

  defp find_user_from_calendar_webhook(_), do: {:error, "No channel token in webhook data"}

  defp find_user_from_hubspot_webhook(%{"portalId" => portal_id}) do
    # For HubSpot webhooks, find user by HubSpot portal connection
    case find_user_with_hubspot_portal(portal_id) do
      %Agentleguide.Accounts.User{} = user -> {:ok, user}
      nil -> {:error, "No user found for HubSpot portal: #{portal_id}"}
    end
  end

  defp find_user_from_hubspot_webhook(_), do: {:error, "No portal ID in webhook data"}

  defp trigger_email_sync(user) do
    # Queue immediate email sync to get the new emails
    Agentleguide.Jobs.EmailSyncJob.schedule_now(user.id)
    {:ok, "email sync triggered"}
  end

  defp fetch_calendar_changes(user, _resource_id) do
    # In a real implementation, you'd fetch specific calendar changes
    # For now, trigger a general calendar sync
    Agentleguide.Jobs.CalendarSyncJob.schedule_now(user.id)
    {:ok, %{type: "calendar_change"}}
  end

  defp fetch_hubspot_object_data(user, object_id, event_type) do
    # In a real implementation, you'd fetch the specific object that changed
    # For now, trigger a general HubSpot sync
    Agentleguide.Jobs.HubspotSyncJob.schedule_now(user.id)
    {:ok, %{object_id: object_id, event_type: event_type}}
  end

  defp find_user_with_calendar_connected do
    # Find any user with calendar connected - in production,
    # you'd want proper token-to-user mapping
    import Ecto.Query

    Agentleguide.Repo.one(
      from u in Agentleguide.Accounts.User,
      where: not is_nil(u.calendar_connected_at),
      limit: 1
    )
  end

  defp find_user_with_hubspot_portal(_portal_id) do
    # Find user with HubSpot connected - in production,
    # you'd want to store portal ID with user mapping
    import Ecto.Query

    Agentleguide.Repo.one(
      from u in Agentleguide.Accounts.User,
      where: not is_nil(u.hubspot_connected_at),
      limit: 1
    )
  end
end

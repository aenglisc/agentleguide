defmodule AgentleguideWeb.HomeLive do
  use AgentleguideWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    current_user = get_current_user(session)

    # Track user as online and start adaptive sync if connected
    if current_user && connected?(socket) do
      Agentleguide.Presence.track_user(self(), current_user.id)

      if current_user.gmail_connected_at do
        maybe_start_background_sync(current_user)
        start_adaptive_email_sync(current_user)
      end
    end

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:messages, [])
      |> assign(:input_message, "")
      |> assign(:loading, false)
      |> assign(:syncing, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    if socket.assigns.current_user && String.trim(message) != "" do
      user_message = %{
        id: System.unique_integer([:positive]),
        content: message,
        role: "user",
        timestamp: DateTime.utc_now()
      }

      socket =
        socket
        |> assign(:messages, socket.assigns.messages ++ [user_message])
        |> assign(:input_message, "")
        |> assign(:loading, true)

      # Send the message to the chat service asynchronously
      send(self(), {:process_message, message})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input_message, message)}
  end

  @impl true
  def handle_info({:process_message, message}, socket) do
    # Generate a session ID if we don't have one
    session_id = Agentleguide.Services.Ai.ChatService.generate_session_id()

    case Agentleguide.Services.Ai.ChatService.process_query(socket.assigns.current_user, session_id, message) do
      {:ok, response} ->
        assistant_message = %{
          id: System.unique_integer([:positive]),
          content: response,
          role: "assistant",
          timestamp: DateTime.utc_now()
        }

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [assistant_message])
          |> assign(:loading, false)

        {:noreply, socket}

      {:error, _reason} ->
        error_message = %{
          id: System.unique_integer([:positive]),
          content: "I'm sorry, I encountered an error processing your message. Please try again.",
          role: "assistant",
          timestamp: DateTime.utc_now()
        }

        socket =
          socket
          |> assign(:messages, socket.assigns.messages ++ [error_message])
          |> assign(:loading, false)

        {:noreply, socket}
    end
  end

  defp maybe_start_background_sync(user) do
    # Don't trigger sync jobs during tests to avoid auth error logs
    if Application.get_env(:agentleguide, :environment) == :test do
      :ok
    else
      # Check if we need to sync emails (if no emails exist or last sync was more than 30 minutes ago)
      emails = Agentleguide.Rag.list_gmail_emails(user)

      should_sync =
        Enum.empty?(emails) ||
          (user.gmail_connected_at &&
             DateTime.diff(DateTime.utc_now(), user.gmail_connected_at, :minute) > 30)

      if should_sync do
        Agentleguide.Jobs.EmailSyncJob.schedule_now(user.id)
      end

      # Also start HubSpot sync if connected
      if user.hubspot_connected_at do
        Agentleguide.Jobs.HubspotSyncJob.schedule_now(user.id)
      end
    end
  end

  defp start_adaptive_email_sync(user) do
    # Don't start adaptive sync during tests
    if Application.get_env(:agentleguide, :environment) == :test do
      :ok
    else
      # Start adaptive email sync (5 seconds when online, 30 minutes when offline)
      Agentleguide.Jobs.EmailSyncJob.start_adaptive_sync(user.id)
    end
  end

  defp get_current_user(%{"user_id" => user_id}) when is_binary(user_id) do
    try do
      Agentleguide.Accounts.get_user!(user_id)
    rescue
      Ecto.NoResultsError -> nil
    end
  end

  defp get_current_user(_), do: nil

  defp format_timestamp(timestamp) do
    timestamp
    |> Calendar.strftime("%H:%M UTC")
  end

  defp format_message_content(content) do
    content
    |> String.split("\n")
    |> Enum.map(&format_line/1)
    |> Enum.join("")
  end

  defp format_line(line) do
    cond do
      # Handle bullet points
      String.match?(line, ~r/^[\s]*[-\*\+]\s+/) ->
        bullet_content = String.replace(line, ~r/^[\s]*[-\*\+]\s+/, "")

        escaped_content =
          Phoenix.HTML.html_escape(bullet_content) |> Phoenix.HTML.safe_to_string()

        "<div class='flex items-start mb-1'><span class='text-gray-400 mr-2 mt-0.5'>•</span><span>#{escaped_content}</span></div>"

      # Handle numbered lists
      String.match?(line, ~r/^[\s]*\d+\.\s+/) ->
        {number, content} = extract_number_and_content(line)
        escaped_content = Phoenix.HTML.html_escape(content) |> Phoenix.HTML.safe_to_string()

        "<div class='flex items-start mb-1'><span class='text-gray-400 mr-2 mt-0.5'>#{number}.</span><span>#{escaped_content}</span></div>"

      # Handle empty lines
      String.trim(line) == "" ->
        "<div class='h-2'></div>"

      # Handle regular lines
      true ->
        escaped_line = Phoenix.HTML.html_escape(line) |> Phoenix.HTML.safe_to_string()
        "<div class='mb-1'>#{escaped_line}</div>"
    end
  end

  defp extract_number_and_content(line) do
    case Regex.run(~r/^[\s]*(\d+)\.\s+(.*)$/, line) do
      [_, number, content] -> {number, content}
      _ -> {"1", line}
    end
  end
end

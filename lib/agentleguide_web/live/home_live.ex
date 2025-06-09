defmodule AgentleguideWeb.HomeLive do
  use AgentleguideWeb, :live_view
  require Logger

  @impl true
  def mount(params, session, socket) do
    current_user = get_current_user(session)

    # Track user as online and start adaptive sync if connected
    if current_user && connected?(socket) do
      Agentleguide.Presence.track_user(self(), current_user.id)

      if current_user.gmail_connected_at do
        maybe_start_background_sync(current_user)
        start_adaptive_email_sync(current_user)
      end
    end

    # Get session_id from params or create new one
    session_id = params["session_id"]

    {messages, current_session, chat_sessions} =
      if current_user && session_id do
        case load_chat_session(current_user, session_id) do
          {:ok, session_data} ->
            sessions = Agentleguide.Services.Ai.ChatService.list_user_sessions(current_user)
            {format_messages_for_display(session_data.messages), session_data.session, sessions}

          {:error, _} ->
            # Session not found, redirect to new session
            sessions = Agentleguide.Services.Ai.ChatService.list_user_sessions(current_user)
            {[], nil, sessions}
        end
      else
        sessions =
          if current_user,
            do: Agentleguide.Services.Ai.ChatService.list_user_sessions(current_user),
            else: []

        {[], nil, sessions}
      end

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:messages, messages)
      |> assign(:current_session, current_session)
      |> assign(:current_session_id, session_id)
      |> assign(:chat_sessions, chat_sessions)
      |> assign(:input_message, "")
      |> assign(:loading, false)
      |> assign(:syncing, false)
      |> assign(:show_session_list, false)

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

      # If we don't have a current session, we'll create one when processing the message
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
  def handle_event("new_session", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, push_navigate(socket, to: ~p"/")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("load_session", %{"session_id" => session_id}, socket) do
    if socket.assigns.current_user do
      {:noreply, push_navigate(socket, to: ~p"/?session_id=#{session_id}")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_session_list", _params, socket) do
    {:noreply, assign(socket, :show_session_list, !socket.assigns.show_session_list)}
  end

  @impl true
  def handle_event("close_session_list", _params, socket) do
    {:noreply, assign(socket, :show_session_list, false)}
  end

  @impl true
  def handle_event("close_session_list_on_escape", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, :show_session_list, false)}
  end

  @impl true
  def handle_event("close_session_list_on_escape", _params, socket) do
    # Ignore other keys
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :input_message, message)}
  end

  @impl true
  def handle_info({:process_message, message}, socket) do
    current_user = socket.assigns.current_user

    # Use existing session ID or create a new one
    session_id =
      socket.assigns.current_session_id ||
        Agentleguide.Services.Ai.ChatService.generate_session_id()

    case Agentleguide.Services.Ai.ChatService.process_query(current_user, session_id, message) do
      {:ok, response} ->
        assistant_message = %{
          id: System.unique_integer([:positive]),
          content: response,
          role: "assistant",
          timestamp: DateTime.utc_now()
        }

        # If this is a new session (no current_session_id), redirect to include session_id in URL
        socket =
          if socket.assigns.current_session_id do
            socket
            |> assign(:messages, socket.assigns.messages ++ [assistant_message])
            |> assign(:loading, false)
          else
            # New session created, redirect to include session_id in URL
            socket
            |> push_navigate(to: ~p"/?session_id=#{session_id}")
          end

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
      # Start historical email sync if not completed (one-time full sync)
      if not user.historical_email_sync_completed do
        Agentleguide.Jobs.HistoricalEmailSyncJob.queue_historical_sync(user)
      end

      # ALSO start recent email sync for immediate access to new emails
      # Check if we need to sync recent emails (last sync was more than 30 minutes ago)
      should_sync =
        user.gmail_last_synced_at == nil ||
          DateTime.diff(DateTime.utc_now(), user.gmail_last_synced_at, :minute) > 30

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
      # Handle code blocks (triple backticks)
      String.match?(line, ~r/^```/) ->
        # For now, just treat as code line - full code block parsing would need more state
        code_content = String.replace(line, ~r/^```\w*/, "")

        if String.trim(code_content) == "" do
          "<div class='h-1'></div>"
        else
          escaped_content =
            Phoenix.HTML.html_escape(code_content) |> Phoenix.HTML.safe_to_string()

          "<div class='bg-gray-100 px-3 py-2 rounded-md font-mono text-sm mb-2'>#{escaped_content}</div>"
        end

      # Handle bullet points
      String.match?(line, ~r/^[\s]*[-\*\+]\s+/) ->
        bullet_content = String.replace(line, ~r/^[\s]*[-\*\+]\s+/, "")
        formatted_content = format_inline_markdown(bullet_content)

        "<div class='flex items-start mb-1'><span class='text-gray-400 mr-2 mt-0.5'>•</span><span>#{formatted_content}</span></div>"

      # Handle numbered lists
      String.match?(line, ~r/^[\s]*\d+\.\s+/) ->
        {number, content} = extract_number_and_content(line)
        formatted_content = format_inline_markdown(content)

        "<div class='flex items-start mb-1'><span class='text-gray-400 mr-2 mt-0.5'>#{number}.</span><span>#{formatted_content}</span></div>"

      # Handle empty lines
      String.trim(line) == "" ->
        "<div class='h-2'></div>"

      # Handle regular lines with markdown formatting
      true ->
        formatted_content = format_inline_markdown(line)
        "<div class='mb-1'>#{formatted_content}</div>"
    end
  end

  defp format_inline_markdown(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> format_bold()
    |> format_italic()
    |> format_code_spans()
    |> format_links()
  end

  # Format **bold** text
  defp format_bold(text) do
    Regex.replace(~r/\*\*(.*?)\*\*/, text, "<strong class='font-semibold'>\\1</strong>")
  end

  # Format *italic* text
  defp format_italic(text) do
    # Use negative lookbehind/lookahead to avoid matching ** patterns
    Regex.replace(~r/(?<!\*)\*(?!\*)([^*]+?)(?<!\*)\*(?!\*)/, text, "<em class='italic'>\\1</em>")
  end

  # Format `code` spans
  defp format_code_spans(text) do
    Regex.replace(
      ~r/`([^`]+?)`/,
      text,
      "<code class='bg-gray-100 px-1 py-0.5 rounded text-sm font-mono'>\\1</code>"
    )
  end

  # Format basic links (simple URL detection)
  defp format_links(text) do
    Regex.replace(
      ~r/(https?:\/\/[^\s]+)/,
      text,
      "<a href='\\1' target='_blank' rel='noopener noreferrer' class='text-blue-600 hover:text-blue-800 underline'>\\1</a>"
    )
  end

  defp extract_number_and_content(line) do
    case Regex.run(~r/^[\s]*(\d+)\.\s+(.*)$/, line) do
      [_, number, content] -> {number, content}
      _ -> {"1", line}
    end
  end

  defp load_chat_session(user, session_id) do
    Agentleguide.Services.Ai.ChatService.get_session_with_messages(user, session_id)
  end

  defp format_messages_for_display(messages) do
    Enum.map(messages, fn message ->
      %{
        id: System.unique_integer([:positive]),
        content: message.content,
        role: message.role,
        timestamp: message.inserted_at
      }
    end)
  end
end

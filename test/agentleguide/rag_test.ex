describe "chat sessions" do
  test "create_chat_session/2 creates a new session with generated title" do
    user = user_fixture()

    {:ok, session} = Rag.create_chat_session(user, %{first_message: "Hello, how are you?"})

    assert session.user_id == user.id
    assert session.title == "Hello, how are you?"
    assert session.is_active == true
    assert session.message_count == 0
    assert session.session_id
  end

  test "create_chat_session/2 truncates long titles" do
    user = user_fixture()
    long_message = String.duplicate("a", 60)

    {:ok, session} = Rag.create_chat_session(user, %{first_message: long_message})

    # 50 chars + "..."
    assert String.length(session.title) == 53
    assert String.ends_with?(session.title, "...")
  end

  test "get_chat_session/2 retrieves session by session_id" do
    user = user_fixture()
    {:ok, session} = Rag.create_chat_session(user, %{first_message: "Test"})

    retrieved = Rag.get_chat_session(user, session.session_id)

    assert retrieved.id == session.id
    assert retrieved.title == "Test"
  end

  test "list_chat_sessions/2 returns user's sessions ordered by activity" do
    user = user_fixture()

    {:ok, session1} = Rag.create_chat_session(user, %{first_message: "First"})
    {:ok, session2} = Rag.create_chat_session(user, %{first_message: "Second"})

    # Update session1 to have more recent activity
    Rag.update_chat_session_activity(user, session1.session_id)

    sessions = Rag.list_chat_sessions(user)

    assert length(sessions) == 2
    # Most recent first
    assert hd(sessions).id == session1.id
  end

  test "update_chat_session_activity/2 updates message count and timestamp" do
    user = user_fixture()
    {:ok, session} = Rag.create_chat_session(user, %{first_message: "Test"})

    original_count = session.message_count

    {:ok, updated} = Rag.update_chat_session_activity(user, session.session_id)

    assert updated.message_count == original_count + 1
    assert updated.last_message_at
  end

  test "archive_chat_session/2 sets is_active to false" do
    user = user_fixture()
    {:ok, session} = Rag.create_chat_session(user, %{first_message: "Test"})

    {:ok, archived} = Rag.archive_chat_session(user, session.session_id)

    assert archived.is_active == false

    # Should not appear in active sessions list
    sessions = Rag.list_chat_sessions(user)
    assert length(sessions) == 0
  end
end

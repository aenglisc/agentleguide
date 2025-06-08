defmodule Agentleguide.Presence do
  @moduledoc """
  Provides presence tracking for users.
  """

  use Phoenix.Presence,
    otp_app: :agentleguide,
    pubsub_server: Agentleguide.PubSub

  @doc """
  Check if a user is currently online.
  """
  def user_online?(user_id) do
    case list("users:#{user_id}") do
      %{} = presences when map_size(presences) > 0 -> true
      _ -> false
    end
  end

  @doc """
  Track a user as online.
  """
  def track_user(pid, user_id, meta \\ %{}) do
    track(pid, "users:#{user_id}", user_id, meta)
  end

  @doc """
  Get all currently online users.
  """
  def list_online_users do
    list("users:")
    |> Map.keys()
    |> Enum.map(&String.replace(&1, "users:", ""))
  end
end

defmodule Agentleguide.Services.Ai.AiClientBehaviour do
  @moduledoc """
  Behaviour for AI client implementations.
  This enables dependency injection and proper testing.
  """

  @doc """
  Generate embeddings for the given text.
  Returns {:ok, embeddings} or {:error, reason}
  """
  @callback generate_embeddings(text :: String.t()) :: {:ok, [float()]} | {:error, any()}

  @doc """
  Generate a chat completion with the given messages.
  Returns {:ok, response} or {:error, reason}
  """
  @callback chat_completion(messages :: [map()], opts :: Keyword.t()) ::
              {:ok, String.t()} | {:error, any()}
end

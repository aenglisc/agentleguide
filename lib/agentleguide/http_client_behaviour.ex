defmodule Agentleguide.HttpClientBehaviour do
  @moduledoc """
  Behaviour for HTTP client operations, allowing for easy mocking of external HTTP calls in tests.
  """

  @callback build(method :: atom(), url :: String.t(), headers :: list(), body :: String.t() | nil) :: any()

  @callback request(request :: any(), finch_name :: any()) ::
              {:ok, %{status: integer(), body: String.t()}} | {:error, any()}
end

defmodule Agentleguide.Repo do
  use Ecto.Repo,
    otp_app: :agentleguide,
    adapter: Ecto.Adapters.Postgres
end

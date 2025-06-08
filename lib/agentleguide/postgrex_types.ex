Postgrex.Types.define(
  Agentleguide.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  json: Jason
)

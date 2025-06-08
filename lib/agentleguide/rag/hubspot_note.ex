defmodule Agentleguide.Rag.HubspotNote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "hubspot_notes" do
    field :hubspot_id, :string
    field :note_type, :string
    field :subject, :string
    field :body, :string
    field :created_date, :utc_datetime
    field :last_modified_date, :utc_datetime
    field :owner_id, :string
    field :properties, :map
    field :last_synced_at, :utc_datetime

    belongs_to :user, Agentleguide.Accounts.User
    belongs_to :contact, Agentleguide.Rag.HubspotContact

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(hubspot_note, attrs) do
    hubspot_note
    |> cast(attrs, [
      :user_id,
      :contact_id,
      :hubspot_id,
      :note_type,
      :subject,
      :body,
      :created_date,
      :last_modified_date,
      :owner_id,
      :properties,
      :last_synced_at
    ])
    |> validate_required([:user_id, :contact_id, :hubspot_id])
    |> unique_constraint([:user_id, :hubspot_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:contact_id)
  end
end

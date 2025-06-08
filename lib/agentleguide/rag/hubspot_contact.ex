defmodule Agentleguide.Rag.HubspotContact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "hubspot_contacts" do
    field :hubspot_id, :string
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :company, :string
    field :job_title, :string
    field :phone, :string
    field :website, :string
    field :city, :string
    field :state, :string
    field :country, :string
    field :lifecycle_stage, :string
    field :lead_status, :string
    field :owner_id, :string
    field :last_modified_date, :utc_datetime
    field :created_date, :utc_datetime
    field :properties, :map
    field :last_synced_at, :utc_datetime

    belongs_to :user, Agentleguide.Accounts.User
    has_many :notes, Agentleguide.Rag.HubspotNote, foreign_key: :contact_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(hubspot_contact, attrs) do
    hubspot_contact
    |> cast(attrs, [
      :user_id,
      :hubspot_id,
      :email,
      :first_name,
      :last_name,
      :company,
      :job_title,
      :phone,
      :website,
      :city,
      :state,
      :country,
      :lifecycle_stage,
      :lead_status,
      :owner_id,
      :last_modified_date,
      :created_date,
      :properties,
      :last_synced_at
    ])
    |> validate_required([:user_id, :hubspot_id])
    |> unique_constraint([:user_id, :hubspot_id])
    |> foreign_key_constraint(:user_id)
  end

  def display_name(%__MODULE__{first_name: first, last_name: last, company: company}) do
    cond do
      first && last -> "#{first} #{last}"
      first -> first
      last -> last
      company -> company
      true -> "Unknown Contact"
    end
  end
end

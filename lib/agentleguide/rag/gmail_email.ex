defmodule Agentleguide.Rag.GmailEmail do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "gmail_emails" do
    field :gmail_id, :string
    field :thread_id, :string
    field :subject, :string
    field :from_email, :string
    field :from_name, :string
    field :to_emails, {:array, :string}
    field :cc_emails, {:array, :string}
    field :bcc_emails, {:array, :string}
    field :body_text, :string
    field :body_html, :string
    field :date, :utc_datetime
    field :labels, {:array, :string}
    field :has_attachments, :boolean, default: false
    field :is_read, :boolean, default: false
    field :is_important, :boolean, default: false
    field :last_synced_at, :utc_datetime

    belongs_to :user, Agentleguide.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(gmail_email, attrs) do
    gmail_email
    |> cast(attrs, [
      :user_id,
      :gmail_id,
      :thread_id,
      :subject,
      :from_email,
      :from_name,
      :to_emails,
      :cc_emails,
      :bcc_emails,
      :body_text,
      :body_html,
      :date,
      :labels,
      :has_attachments,
      :is_read,
      :is_important,
      :last_synced_at
    ])
    |> validate_required([:user_id, :gmail_id])
    |> unique_constraint([:user_id, :gmail_id])
    |> foreign_key_constraint(:user_id)
  end
end

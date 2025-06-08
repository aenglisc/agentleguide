defmodule Agentleguide.Tasks.OngoingInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ongoing_instructions" do
    field :instruction, :string
    field :is_active, :boolean, default: true
    field :priority, :integer, default: 1

    belongs_to :user, Agentleguide.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(ongoing_instruction, attrs) do
    ongoing_instruction
    |> cast(attrs, [:user_id, :instruction, :is_active, :priority])
    |> validate_required([:user_id, :instruction])
    |> validate_number(:priority, greater_than: 0)
    |> foreign_key_constraint(:user_id)
  end
end

defmodule ShareCircle.Families.Membership do
  @moduledoc "A user's membership in a family, including their role."

  use Ecto.Schema
  import Ecto.Changeset

  alias ShareCircle.Accounts.User
  alias ShareCircle.Families.{Family, Role}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "memberships" do
    belongs_to :family, Family
    belongs_to :user, User

    field :role, :string
    field :nickname, :string
    field :relationship_label, :string
    field :joined_at, :utc_datetime_usec
    field :last_read_feed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :nickname])
    |> validate_required([:role])
    |> validate_inclusion(:role, Role.all(),
      message: "must be one of: #{Enum.join(Role.all(), ", ")}"
    )
  end

  def relationship_label_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:relationship_label])
    |> validate_length(:relationship_label, max: 50)
  end
end

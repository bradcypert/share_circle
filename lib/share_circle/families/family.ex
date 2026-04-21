defmodule ShareCircle.Families.Family do
  @moduledoc "A family — the top-level unit of isolation and tenancy."

  use Ecto.Schema
  import Ecto.Changeset

  alias ShareCircle.Families.Membership

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "families" do
    field :name, :string
    field :slug, :string
    field :timezone, :string, default: "UTC"
    field :settings, :map, default: %{}
    field :storage_quota_bytes, :integer, default: 10_737_418_240
    field :storage_used_bytes, :integer, default: 0
    field :member_limit, :integer, default: 50
    field :deleted_at, :utc_datetime_usec

    has_many :memberships, Membership

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name, :slug, :timezone, :settings, :member_limit])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:slug, min: 2, max: 50)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "only lowercase letters, numbers, and hyphens"
    )
    |> unique_constraint(:slug)
  end
end

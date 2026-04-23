defmodule ShareCircle.Notifications.NotificationPreference do
  use Ecto.Schema
  import Ecto.Changeset

  alias ShareCircle.Accounts.User
  alias ShareCircle.Families.Family

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "notification_preferences" do
    belongs_to :user, User
    belongs_to :family, Family

    field :kind, :string
    field :channels, :map, default: %{"in_app" => true, "email" => false, "push" => true}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(pref, attrs) do
    pref
    |> cast(attrs, [:user_id, :family_id, :kind, :channels])
    |> validate_required([:user_id, :kind, :channels])
    |> unique_constraint([:user_id, :family_id, :kind])
  end
end

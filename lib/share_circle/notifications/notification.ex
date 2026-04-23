defmodule ShareCircle.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias ShareCircle.Accounts.User
  alias ShareCircle.Families.Family

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  @valid_kinds ~w(new_post new_comment new_message reaction event_invite event_created rsvp_changed member_joined member_left role_changed)

  schema "notifications" do
    belongs_to :family, Family
    belongs_to :recipient_user, User
    belongs_to :actor_user, User

    field :kind, :string
    field :subject_type, :string
    field :subject_id, Ecto.UUID
    field :payload, :map, default: %{}
    field :read_at, :utc_datetime_usec

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:family_id, :recipient_user_id, :actor_user_id, :kind,
                    :subject_type, :subject_id, :payload])
    |> validate_required([:family_id, :recipient_user_id, :kind])
    |> validate_inclusion(:kind, @valid_kinds)
  end
end

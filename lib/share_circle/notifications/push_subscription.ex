defmodule ShareCircle.Notifications.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias ShareCircle.Accounts.User

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  schema "push_subscriptions" do
    belongs_to :user, User

    field :endpoint, :string
    field :p256dh_key, :string
    field :auth_key, :string
    field :user_agent, :string
    field :last_used_at, :utc_datetime_usec

    field :inserted_at, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:user_id, :endpoint, :p256dh_key, :auth_key, :user_agent])
    |> validate_required([:user_id, :endpoint, :p256dh_key, :auth_key])
    |> unique_constraint([:user_id, :endpoint])
  end
end

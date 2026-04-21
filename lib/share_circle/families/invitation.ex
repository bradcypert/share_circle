defmodule ShareCircle.Families.Invitation do
  @moduledoc "An email invitation to join a family."

  use Ecto.Schema
  import Ecto.Changeset

  alias ShareCircle.Accounts.User
  alias ShareCircle.Families.{Family, Role}

  @rand_size 32
  @validity_in_days 7

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invitations" do
    belongs_to :family, Family
    belongs_to :invited_by_user, User
    belongs_to :accepted_by_user, User

    field :email, :string
    field :role, :string
    field :token, :binary
    field :accepted_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Builds a new invitation with a random token. Returns {url_token, invitation}."
  def build(family_id, invited_by_user_id, attrs) do
    raw_token = :crypto.strong_rand_bytes(@rand_size)
    url_token = Base.url_encode64(raw_token, padding: false)
    hashed_token = :crypto.hash(:sha256, raw_token)
    expires_at = DateTime.add(DateTime.utc_now(), @validity_in_days, :day)

    changeset =
      %__MODULE__{}
      |> cast(attrs, [:email, :role])
      |> validate_required([:email, :role])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
      |> validate_inclusion(:role, Role.all())
      |> put_change(:family_id, family_id)
      |> put_change(:invited_by_user_id, invited_by_user_id)
      |> put_change(:token, hashed_token)
      |> put_change(:expires_at, expires_at)

    {url_token, changeset}
  end

  def pending?(%__MODULE__{accepted_at: nil, revoked_at: nil, expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  def pending?(_), do: false
end

defmodule ShareCircle.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :authenticated_at, :utc_datetime_usec, virtual: true

    field :display_name, :string
    field :timezone, :string, default: "UTC"
    field :locale, :string, default: "en-US"
    field :is_admin, :boolean, default: false
    field :is_supervised, :boolean, default: false
    field :promoted_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :guardian, __MODULE__, foreign_key: :guardian_user_id, type: :binary_id

    field :bio, :string
    field :location, :string
    field :birthday, :date
    field :interests, :string

    belongs_to :avatar_media_item, ShareCircle.Media.MediaItem,
      foreign_key: :avatar_media_item_id,
      type: :binary_id

    belongs_to :cover_media_item, ShareCircle.Media.MediaItem,
      foreign_key: :cover_media_item_id,
      type: :binary_id

    belongs_to :pinned_post, ShareCircle.Posts.Post,
      foreign_key: :pinned_post_id,
      type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for initial registration — requires email, password, and display_name."
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :display_name])
    |> validate_required([:display_name])
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc "Changeset for magic-link registration — requires email and display_name, no password."
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :display_name])
    |> validate_required([:display_name])
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_email(opts)
  end

  @doc "Changeset for changing password only."
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc "Changeset for updating profile fields."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :display_name,
      :timezone,
      :locale,
      :bio,
      :location,
      :birthday,
      :interests,
      :avatar_media_item_id,
      :cover_media_item_id,
      :pinned_post_id
    ])
    |> validate_required([:display_name])
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_length(:bio, max: 300)
    |> validate_length(:location, max: 100)
    |> validate_length(:interests, max: 300)
  end

  @doc "Changeset for guardian-created supervised accounts. No password required at creation."
  def supervised_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :display_name, :guardian_user_id])
    |> validate_required([:display_name, :guardian_user_id])
    |> validate_length(:display_name, min: 1, max: 100)
    |> validate_email([])
    |> put_change(:is_supervised, true)
  end

  @doc "Changeset for a child completing first-time account activation (sets password, optionally changes email)."
  def activation_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email_if_changed(opts)
    |> validate_password(opts)
    |> put_change(:confirmed_at, DateTime.utc_now(:microsecond))
  end

  @doc "Changeset for completing promotion: new password, optional email update, clears supervised flag."
  def promotion_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email_if_changed(opts)
    |> validate_password(opts)
    |> put_change(:is_supervised, false)
    |> put_change(:promoted_at, DateTime.utc_now(:microsecond))
    |> put_change(:confirmed_at, user.confirmed_at || DateTime.utc_now(:microsecond))
  end

  @doc "Confirms the account by setting confirmed_at."
  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now(:microsecond))
  end

  @doc "Returns true if the given password matches the user's stored hash."
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  defp validate_email_if_changed(changeset, opts) do
    case get_change(changeset, :email) do
      nil -> changeset
      _ -> validate_email(changeset, opts)
    end
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_length(:email, max: 160)
    |> then(fn cs ->
      if Keyword.get(opts, :validate_unique, true) do
        cs
        |> unsafe_validate_unique(:email, ShareCircle.Repo)
        |> unique_constraint(:email)
        |> validate_email_changed()
      else
        cs
      end
    end)
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 256)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end

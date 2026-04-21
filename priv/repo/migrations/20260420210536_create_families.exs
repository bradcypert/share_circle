defmodule ShareCircle.Repo.Migrations.CreateFamilies do
  use Ecto.Migration

  def change do
    create table(:families, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :citext, null: false
      add :timezone, :string, null: false, default: "UTC"
      add :settings, :map, null: false, default: %{}
      add :storage_quota_bytes, :bigint, null: false, default: 10_737_418_240
      add :storage_used_bytes, :bigint, null: false, default: 0
      add :member_limit, :integer, null: false, default: 50
      add :deleted_at, :utc_datetime_usec

      # avatar_media_id added once media_items exists

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:families, [:slug], where: "deleted_at IS NULL")

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :family_id, references(:families, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :nickname, :string
      add :joined_at, :utc_datetime_usec, null: false
      add :last_read_feed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memberships, [:family_id, :user_id])
    create index(:memberships, [:family_id])
    create index(:memberships, [:user_id])

    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :family_id, references(:families, type: :binary_id, on_delete: :delete_all), null: false

      add :invited_by_user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :email, :citext, null: false
      add :role, :string, null: false
      add :token, :binary, null: false
      add :accepted_at, :utc_datetime_usec
      add :accepted_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :revoked_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invitations, [:token])
    create index(:invitations, [:family_id])

    # Efficiently find open invitations for a given email
    create index(:invitations, [:email], where: "accepted_at IS NULL AND revoked_at IS NULL")
  end
end

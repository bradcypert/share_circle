defmodule ShareCircle.Repo.Migrations.CreateNotificationTables do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :family_id, references(:families, type: :binary_id, on_delete: :delete_all), null: false
      add :recipient_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :kind, :text, null: false
      add :subject_type, :text
      add :subject_id, :binary_id
      add :payload, :map, null: false, default: %{}
      add :read_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:notifications, [:recipient_user_id, :inserted_at],
             where: "read_at IS NULL",
             name: :notifications_recipient_unread)

    create index(:notifications, [:recipient_user_id, :inserted_at],
             name: :notifications_recipient_all)

    create table(:notification_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :family_id, references(:families, type: :binary_id, on_delete: :delete_all)
      add :kind, :text, null: false
      add :channels, :map, null: false, default: %{in_app: true, email: false, push: true}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:notification_preferences, [:user_id, :family_id, :kind])

    create table(:push_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :endpoint, :text, null: false
      add :p256dh_key, :text, null: false
      add :auth_key, :text, null: false
      add :user_agent, :text
      add :last_used_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:push_subscriptions, [:user_id, :endpoint])
  end
end

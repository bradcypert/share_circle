defmodule ShareCircle.Repo.Migrations.AddSupervisedAccounts do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_supervised, :boolean, null: false, default: false
      add :guardian_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :promoted_at, :utc_datetime_usec
    end

    create index(:users, [:guardian_user_id])
  end
end

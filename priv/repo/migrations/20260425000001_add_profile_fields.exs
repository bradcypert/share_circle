defmodule ShareCircle.Repo.Migrations.AddProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bio, :text
      add :location, :string, size: 100
      add :birthday, :date
      add :interests, :string, size: 300
      add :avatar_media_item_id, references(:media_items, type: :uuid, on_delete: :nilify_all)
      add :cover_media_item_id, references(:media_items, type: :uuid, on_delete: :nilify_all)
      add :pinned_post_id, references(:posts, type: :uuid, on_delete: :nilify_all)
    end

    alter table(:memberships) do
      add :relationship_label, :string, size: 50
    end

    create index(:users, [:avatar_media_item_id])
    create index(:users, [:cover_media_item_id])
    create index(:users, [:pinned_post_id])
  end
end

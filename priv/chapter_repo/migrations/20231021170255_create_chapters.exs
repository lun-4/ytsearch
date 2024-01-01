defmodule YtSearch.Repo.Migrations.CreateChapters do
  use Ecto.Migration

  def change do
    create table(:chapters) do
      add :youtube_id, :string, primary_key: true, autogenerate: false
      add :chapter_data, :string
      timestamps()
    end

    create index(:chapters, ["unixepoch(inserted_at)"])
  end
end

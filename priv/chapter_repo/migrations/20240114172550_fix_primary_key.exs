defmodule YtSearch.ChapterRepo.Migrations.FixPrimaryKey do
  use Ecto.Migration

  def change do
    create table(:chapters_v2, primary_key: false) do
      add :youtube_id, :string, primary_key: true, autogenerate: false
      add :chapter_data, :string
      timestamps()
    end

    create index(:chapters_v2, ["unixepoch(inserted_at)"])
  end
end

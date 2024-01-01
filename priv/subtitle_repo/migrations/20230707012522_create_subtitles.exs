defmodule YtSearch.Repo.Migrations.CreateSubtitles do
  use Ecto.Migration

  def change do
    create table(:subtitles, primary_key: false) do
      add :youtube_id, :string, primary_key: true, autogenerate: false
      add :language, :string, primary_key: true
      add :subtitle_data, :string
      timestamps()
    end

    create index(:subtitles, ["unixepoch(inserted_at)"])
  end
end

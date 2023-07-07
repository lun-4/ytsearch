defmodule YtSearch.Repo.Migrations.CreateSubtitles do
  use Ecto.Migration

  def change do
    create table(:subtitles) do
      add :youtube_id, :string, primary_key: true, autogenerate: false
      add :language, :string, primary_key: true
      add :subtitle_data, :string
      timestamps()
    end
  end
end

defmodule YtSearch.Repo.Migrations.AddUnixepochIndexesOnSubtitlesAndThumbnails do
  use Ecto.Migration

  def change do
    create index(:subtitles, ["unixepoch(inserted_at)"])
    create index(:thumbnails, ["unixepoch(inserted_at)"])
  end
end

defmodule YtSearch.Repo.Migrations.AddYoutubeMetadataToLinks do
  use Ecto.Migration

  def change do
    alter table(:links) do
      add :youtube_metadata, :string
    end
  end
end

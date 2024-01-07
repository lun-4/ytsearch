defmodule YtSearch.Repo.Migrations.CreateLinks do
  use Ecto.Migration

  def change do
    create table(:links, primary_key: false) do
      add :youtube_id, :string, primary_key: true, autogenerate: false
      add :mp4_link, :string
      add :error_reason, :string
      add :youtube_metadata, :string
      timestamps()
    end

    create index(:links, ["unixepoch(inserted_at)"])
  end
end

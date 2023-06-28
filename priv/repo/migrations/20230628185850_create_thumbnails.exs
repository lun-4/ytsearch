defmodule YtSearch.Repo.Migrations.CreateThumbnails do
  use Ecto.Migration

  def change do
    create table(:thumbnails, primary_key: false) do
      add :id, :string, primary_key: true, autogenerate: false
      add :mime_type, :string
      add :data, :blob
      timestamps()
    end
  end
end

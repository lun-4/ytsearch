defmodule YtSearch.Repo.Migrations.AddMissingIndex do
  use Ecto.Migration

  def change do
    create index(:audio_configs, ["unixepoch(inserted_at)"])
  end
end

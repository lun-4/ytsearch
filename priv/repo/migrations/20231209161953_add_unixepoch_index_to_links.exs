defmodule YtSearch.Repo.Migrations.AddUnixepochIndexToLinks do
  use Ecto.Migration

  def change do
    create index(:links, ["unixepoch(inserted_at)"])
  end
end

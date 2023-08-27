defmodule YtSearch.Repo.Migrations.AddUnixepochIndexesOnAllSlots do
  use Ecto.Migration

  def change do
    create index(:channel_slots, ["unixepoch(inserted_at)"])
    create index(:search_slots, ["unixepoch(inserted_at)"])
    create index(:playlist_slots, ["unixepoch(inserted_at)"])
  end
end

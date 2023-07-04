defmodule YtSearch.Repo.Migrations.CreatePlaylistSlots do
  use Ecto.Migration

  def change do
    create table(:playlist_slots, primary_key: false) do
      add :id, :integer, primary_key: true, autogenerate: false
      add :youtube_id, :string
      timestamps()
    end
  end
end

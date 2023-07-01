defmodule YtSearch.Repo.Migrations.CreateChannelSlots do
  use Ecto.Migration

  def change do
    create table(:channel_slots, primary_key: false) do
      add :id, :integer, primary_key: true, autogenerate: false
      add :youtube_id, :string
      timestamps()
    end
  end
end

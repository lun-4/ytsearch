defmodule YtSearch.Repo.Migrations.AddYoutubeIdIndexOnChannelSlots do
  use Ecto.Migration

  def change do
    create index(:channel_slots, [:youtube_id])
  end
end

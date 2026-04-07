defmodule YtSearch.Data.TrendingRepo.Migrations.AddVideoViews do
  use Ecto.Migration

  def change do
    create table(:video_views) do
      add(:yt_video_id, :string, null: false)
      add(:viewed_at, :naive_datetime, null: false)
    end

    create index(:video_views, ["unixepoch(viewed_at)"])
  end
end

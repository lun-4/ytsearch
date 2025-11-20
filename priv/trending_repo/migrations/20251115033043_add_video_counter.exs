defmodule YtSearch.Data.TrendingRepo.Migrations.AddVideoCounter do
  use Ecto.Migration

  def change do
    create table(:video_counter, primary_key: false) do
      add(:yt_video_id, :string, primary_key: true)
      add(:view_count, :integer, default: 0)
    end

    create index(:video_counter, [:view_count])
  end
end

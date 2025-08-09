defmodule YtSearch.Data.SubtitleRepo.Migrations.AddCta do
  use Ecto.Migration

  def change do
    alter table(:subtitles) do
      add(:cta, :map)
    end
  end
end

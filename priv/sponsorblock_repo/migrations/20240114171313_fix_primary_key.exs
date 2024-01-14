defmodule YtSearch.SponsorblockRepo.Migrations.FixPrimaryKey do
  use Ecto.Migration

  def change do
    create table(:sponsorblock_segments_v2, primary_key: false) do
      add(:youtube_id, :string, primary_key: true, autogenerate: false)
      add(:segments_json, :string)
      timestamps()
    end

    create(index(:sponsorblock_segments_v2, ["unixepoch(inserted_at)"]))
  end
end

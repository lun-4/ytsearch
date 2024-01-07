defmodule YtSearch.Repo.Migrations.AddSponsorblockSegmentsTable do
  use Ecto.Migration

  def change do
    create table(:sponsorblock_segments) do
      add(:youtube_id, :string, primary_key: true, autogenerate: false)
      add(:segments_json, :string)
      timestamps()
    end

    create(index(:sponsorblock_segments, ["unixepoch(inserted_at)"]))
  end
end

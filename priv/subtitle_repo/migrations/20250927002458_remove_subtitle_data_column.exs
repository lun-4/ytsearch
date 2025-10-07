defmodule YtSearch.Data.SubtitleRepo.Migrations.RemoveSubtitleDataColumn do
  use Ecto.Migration

  def change do
    # truncate the table since none of the subs will exist on disk
    execute("DELETE FROM subtitles", "")

    # remove the data column
    alter table(:subtitles) do
      remove(:subtitle_data, :string)
    end

    # note: should manually run a vacuum after this
  end
end

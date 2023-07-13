defmodule YtSearch.Repo.Migrations.AddVideoDurationToSlots do
  use Ecto.Migration

  def change do
    alter table(:slots_v2) do
      add :video_duration, :integer
    end
  end
end

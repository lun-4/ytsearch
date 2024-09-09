defmodule YtSearch.Data.SearchSlotRepo.Migrations.AddResultTypeAndTitle do
  use Ecto.Migration

  def change do
    alter table(:search_slots_v3) do
      add :result_type, :string
      add :result_title, :string
    end
  end
end

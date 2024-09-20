defmodule YtSearch.Data.SearchSlotRepo.Migrations.AddNextpageDataIndex do
  use Ecto.Migration

  def change do
    create index(:search_slots_v3, :nextpage_data)
  end
end

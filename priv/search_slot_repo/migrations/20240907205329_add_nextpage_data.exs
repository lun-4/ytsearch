defmodule YtSearch.Data.SearchSlotRepo.Migrations.AddNextpageData do
  use Ecto.Migration

  def change do
    alter table(:search_slots_v3) do
      add :nextpage_data, :text
      add :type, :text
      add :nextpage_slot_id, :integer
    end
  end
end

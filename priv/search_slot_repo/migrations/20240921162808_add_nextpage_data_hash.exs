defmodule YtSearch.Data.SearchSlotRepo.Migrations.AddNextpageDataHash do
  use Ecto.Migration

  def change do
    alter table(:search_slots_v3) do
      add :nextpage_data_hash, :text, default: nil
    end

    drop index(:search_slots_v3, :nextpage_data)
    create index(:search_slots_v3, :nextpage_data_hash)
  end
end

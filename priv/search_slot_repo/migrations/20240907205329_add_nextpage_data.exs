defmodule YtSearch.Data.SearchSlotRepo.Migrations.AddNextpageData do
  use Ecto.Migration

  def change do
    alter table(:search_slots_v3) do
      add :nextpage_data, :text
      add :type, :text
      add :slots_json_v2, :text, null: true
    end
  end
end

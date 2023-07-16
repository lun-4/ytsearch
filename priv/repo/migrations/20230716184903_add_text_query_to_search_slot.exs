defmodule YtSearch.Repo.Migrations.AddTextQueryToSearchSlot do
  use Ecto.Migration

  def change do
    alter table(:search_slots) do
      add :query, :string
    end
  end
end

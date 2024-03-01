defmodule YtSearch.Repo.Migrations.AddTypeToSlot do
  use Ecto.Migration

  def change do
    alter table(:slots_v3) do
      add :type, :integer, null: false, default: 0
    end
  end
end

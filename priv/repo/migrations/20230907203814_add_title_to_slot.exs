defmodule YtSearch.Repo.Migrations.AddTitleToSlot do
  use Ecto.Migration

  def change do
    alter table(:slots_v2) do
      add :title, :string
    end
  end
end

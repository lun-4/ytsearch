defmodule YtSearch.Repo.Migrations.CreateSearchSlots do
  use Ecto.Migration

  def change do
    create table(:search_slots, primary_key: false) do
      add :id, :integer, primary_key: true, autogenerate: false
      add :slots_json, :string
      timestamps()
    end
  end
end

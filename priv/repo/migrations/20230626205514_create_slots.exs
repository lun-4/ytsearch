defmodule YtSearch.Repo.Migrations.CreateSlots do
  use Ecto.Migration

  def change do
    create table(:slots, primary_key: false) do
      add :id, :integer, primary_key: true, autogenerate: false
      add :youtube_id, :string, unique: true
    end
  end
end

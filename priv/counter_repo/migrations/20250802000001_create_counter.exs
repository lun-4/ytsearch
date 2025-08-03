defmodule YtSearch.Data.CounterRepo.Migrations.CreateCounter do
  use Ecto.Migration

  def change do
    create table(:counter, primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:value, :integer, default: 0, null: false)

      timestamps()
    end
  end
end

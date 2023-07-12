defmodule YtSearch.Repo.Migrations.UseIntsAsSlotTimestamps do
  use Ecto.Migration

  def up do
    alter table(:slots_v2) do
      # just want to get a new inserted_at
      timestamps(
        inserted_at: :inserted_at_v2,
        updated_at: false,
        type: :integer,
        default: 0
      )
    end

    create index(:slots_v2, [:inserted_at_v2], comment: "fast queries for the slow case for slots")

    execute("UPDATE slots_v2 SET inserted_at_v2 = unixepoch(inserted_at)")
  end

  def down do
    alter table(:slots_v2) do
      remove :inserted_at_v2
    end

    drop index(:slots_v2, [:inserted_at_v2])
  end
end

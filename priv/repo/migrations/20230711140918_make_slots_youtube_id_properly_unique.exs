defmodule YtSearch.Repo.Migrations.MakeSlotsYoutubeIdProperlyUnique do
  use Ecto.Migration
  require Logger

  defmodule OldSlot do
    use Ecto.Schema
    import Ecto.Changeset
    import Ecto.Query
    import Ecto, only: [assoc: 2]
    require Logger

    @type t :: %__MODULE__{}

    @primary_key {:id, :integer, autogenerate: false}

    schema "slots" do
      field(:youtube_id, :string)
      Ecto.Schema.timestamps()
    end
  end

  defmodule NewSlot do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :integer, autogenerate: false}

    schema "slots_v2" do
      field(:youtube_id, :string)
      Ecto.Schema.timestamps()
    end

    def from_old_slot(slot) do
      %__MODULE__{
        id: slot.id,
        youtube_id: slot.youtube_id,
        inserted_at: slot.inserted_at,
        updated_at: slot.updated_at
      }
    end

    def changeset(new_slot, params \\ %{}) do
      new_slot
      |> cast(params, [:id, :youtube_id])
      |> validate_required([:youtube_id])
      |> unique_constraint(:id)
      |> unique_constraint(:youtube_id)
    end
  end

  defp lock_table(table) do
    Logger.info(
      "manual action required to lock #{table} table (as using it is now invalid). run following sql:"
    )

    lockquery = "CREATE TRIGGER IF NOT EXISTS #{table}_readonly_update
             BEFORE UPDATE ON #{table}
             BEGIN
                 SELECT raise(abort, 'this is a software bug, use #{table}_v2 table');
             END;
            
             CREATE TRIGGER IF NOT EXISTS #{table}_readonly_insert
             BEFORE INSERT ON #{table}
             BEGIN
                 SELECT raise(abort, 'this is a software bug, use #{table}_v2 table');
             END;
            
             CREATE TRIGGER IF NOT EXISTS #{table}_readonly_delete
             BEFORE DELETE ON #{table}
             BEGIN
                 SELECT raise(abort, 'this is a software bug, use #{table}_v2 table');
             END;"
    Logger.info("#{lockquery}")
  end

  def up do
    create table(:slots_v2, primary_key: false) do
      add :id, :integer, primary_key: true, autogenerate: false
      add :youtube_id, :string, null: false
      timestamps()
    end

    create unique_index(:slots_v2, [:youtube_id])

    # migrate all old slots to new table

    execute(fn ->
      import Ecto.Query

      stream =
        repo().stream(
          from(s in OldSlot,
            select: s,
            order_by: [desc: fragment("unixepoch(?)", s.inserted_at)]
          )
        )

      repo().transaction(fn ->
        Enum.each(stream, fn slot ->
          slot
          |> NewSlot.from_old_slot()
          |> NewSlot.changeset()
          |> repo().insert
        end)
      end)
    end)

    execute(fn ->
      lock_table(:slots)
    end)
  end

  def down do
    Logger.warn(
      "if the `ecto.migrate` command failed, you need to know if it failed before or after the main execute/1 call, if it failed after, you lost data."
    )

    drop unique_index(:slots_v2, [:youtube_id])
    drop table(:slots_v2)
  end
end

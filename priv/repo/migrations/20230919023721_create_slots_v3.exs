defmodule YtSearch.Repo.Migrations.CreateSlotsV3 do
  use Ecto.Migration

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  def up do
    create table(:slots_v3, primary_key: false) do
      add :id, :integer, autogenerate: false, primary_key: true
      add(:youtube_id, :string)
      add(:video_duration, :integer, null: false)
      timestamps()

      add(:expires_at, :naive_datetime, null: false)
      add(:used_at, :naive_datetime, null: false)
      add(:keepalive, :boolean, null: false)
    end

    create unique_index(:slots_v3, [:youtube_id])
    # TODO indexes on expires_at,used_at
    # TODO do i need index on keepalive?

    execute fn ->
      repo().transaction(fn ->
        0..99999
        |> Enum.map(fn id ->
          %{
            id: id,
            youtube_id: random_yt_id(),
            expires_at: ~N[2020-01-01 00:00:00],
            used_at: ~N[2020-01-01 00:00:00],
            inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
            updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
            keepalive: false
          }
        end)
        |> Enum.chunk_every(5000)
        |> Enum.each(fn batch ->
          repo().insert_all(YtSearch.Slot, batch)
        end)
      end)
    end

    # TODO all other slot tables
  end

  def down do
    remove table(:slots_v3)
  end
end

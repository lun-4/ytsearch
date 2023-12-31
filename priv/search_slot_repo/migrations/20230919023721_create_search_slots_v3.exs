defmodule YtSearch.Repo.Migrations.CreateSearchSlotsV3 do
  use Ecto.Migration

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  def up do
    create table(:search_slots_v3) do
      add(:query, :string)
      add(:slots_json, :string, null: false)
      timestamps()

      add(:expires_at, :naive_datetime, null: false)
      add(:used_at, :naive_datetime, null: false)
      add(:keepalive, :boolean, null: false)
    end

    create unique_index(:search_slots_v3, [:query])
    create index(:search_slots_v3, ["unixepoch(expires_at)"])
    create index(:search_slots_v3, ["unixepoch(used_at)"])

    execute fn ->
      repo().transaction(
        fn ->
          [YtSearch.SearchSlot]
          |> Enum.each(fn module ->
            0..(module.slot_spec().max_ids - 1)
            |> Enum.map(fn id ->
              %{
                id: id,
                query: random_yt_id(),
                expires_at: ~N[2020-01-01 00:00:00],
                used_at: ~N[2020-01-01 00:00:00],
                slots_json: "[]",
                inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
                updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
                keepalive: false
              }
            end)
            |> Enum.chunk_every(100)
            |> Enum.each(fn batch ->
              repo().insert_all(module, batch, timeout: :infinity)
            end)
          end)
        end,
        timeout: :infinity
      )
    end
  end

  def down do
    drop_if_exists table(:search_slots_v3)
  end
end

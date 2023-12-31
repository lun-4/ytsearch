defmodule YtSearch.Repo.Migrations.CreateChannelSlotsV3 do
  use Ecto.Migration

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  def up do
    create table(:channel_slots_v3) do
      add(:youtube_id, :string)
      timestamps()

      add(:expires_at, :naive_datetime, null: false)
      add(:used_at, :naive_datetime, null: false)
      add(:keepalive, :boolean, null: false)
    end

    create unique_index(:channel_slots_v3, [:youtube_id])

    create index(:channel_slots_v3, ["unixepoch(expires_at)"])
    create index(:channel_slots_v3, ["unixepoch(used_at)"])

    execute fn ->
      repo().transaction(
        fn ->
          [YtSearch.ChannelSlot]
          |> Enum.each(fn module ->
            0..(module.slot_spec().max_ids - 1)
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
    drop_if_exists table(:channel_slots_v3)
  end
end

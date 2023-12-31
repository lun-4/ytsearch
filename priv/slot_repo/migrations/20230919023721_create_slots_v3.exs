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

    create index(:slots_v3, ["unixepoch(expires_at)"])
    create index(:slots_v3, ["unixepoch(used_at)"])

    execute fn ->
      repo().transaction(
        fn ->
          [YtSearch.Slot]
          |> Enum.each(fn module ->
            0..(module.slot_spec().max_ids - 1)
            |> Enum.map(fn id ->
              case module do
                YtSearch.Slot ->
                  %{
                    id: id,
                    youtube_id: random_yt_id(),
                    expires_at: ~N[2020-01-01 00:00:00],
                    used_at: ~N[2020-01-01 00:00:00],
                    video_duration: 60,
                    inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
                    updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
                    keepalive: false
                  }
              end
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

    default_expires_now =
      NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
  end

  def down do
    drop_if_exists table(:slots_v3)
  end
end

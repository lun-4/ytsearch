defmodule Mix.Tasks.YtSearch.RecoverIds do
  use Mix.Task
  import Ecto.Query

  @requirements ["app.start"]

  defp random_yt_id do
    :rand.uniform(100_000_000_000_000) |> to_string |> Base.encode64()
  end

  def start_repo do
    [:ecto, :ecto_sql, :exqlite, :db_connection]
    |> Enum.each(fn app -> Application.ensure_all_started(app) end)

    children = [
      YtSearch.Repo
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: YtSearch.Supervisor
    )
  end

  def run([]) do
    start_repo()

    [YtSearch.Slot, YtSearch.ChannelSlot, YtSearch.PlaylistSlot, YtSearch.SearchSlot]
    |> Enum.each(fn module ->
      IO.puts("working #{module}...")

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

          YtSearch.SearchSlot ->
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

          s when s in [YtSearch.ChannelSlot, YtSearch.PlaylistSlot] ->
            %{
              id: id,
              youtube_id: random_yt_id(),
              expires_at: ~N[2020-01-01 00:00:00],
              used_at: ~N[2020-01-01 00:00:00],
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
              keepalive: false
            }
        end
      end)
      |> Enum.chunk_every(200)
      |> Enum.map(fn chunk ->
        first = chunk |> Enum.at(0)
        last = chunk |> Enum.at(-1)

        IO.puts("insert chunk ids #{first.id}..#{last.id}")

        {amount_inserted, nil} = YtSearch.Repo.insert_all(module, chunk, on_conflict: :nothing)
        amount_inserted
      end)
      |> Enum.reduce(fn x, y -> x + y end)
      |> then(fn len ->
        IO.puts("worked #{module}, inserted #{len} slots")
      end)
    end)
  end
end

defmodule Mix.Tasks.YtSearch.DoubleCheckThumbnails do
  require Ecto.Query
  alias YtSearch.Thumbnail
  require Logger
  use Mix.Task

  def start_repo do
    [:ecto, :ecto_sql, :exqlite, :db_connection, :logger]
    |> Enum.each(fn app -> Application.ensure_all_started(app) end)

    children = [
      YtSearch.Data.ThumbnailRepo,
      YtSearch.Data.ThumbnailRepo.Replica1,
      YtSearch.Data.ThumbnailRepo.Replica2
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: YtSearch.Supervisor
    )
  end

  def run([chunk_size]) do
    start_repo()
    {chunk_size, ""} = chunk_size |> Integer.parse()

    Path.wildcard("thumbnails/*")
    |> then(fn thumbs ->
      Logger.info("there are #{length(thumbs)} thumbnails in the folder")
      thumbs
    end)
    |> Enum.chunk_every(chunk_size)
    |> Enum.each(fn chunk ->
      Logger.info("processing #{length(chunk)} files")

      chunk
      |> Enum.each(fn thumbnail_path ->
        [_, ytid] = thumbnail_path |> String.split("/")

        # Thumbnail.fetch does not need to do TTL checks (on purpose, as we can serve the same thumb
        # but maybe not the same link or subtitle),
        # so a direct fetch() will match db behavior exactly.

        metadata? = Thumbnail.fetch(ytid)

        if metadata? == nil do
          Logger.info("thumbnail #{ytid} does not exist in db, removing")
          File.rm(thumbnail_path)
        end
      end)

      Logger.info("waiting 20 seconds until next chunk...")
      :timer.sleep(20000)
    end)

    Logger.info("done!")
  end
end

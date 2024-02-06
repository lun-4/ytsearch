defmodule Mix.Tasks.YtSearch.DoubleCheckThumbnails do
  require Ecto.Query
  alias YtSearch.Thumbnail
  require Logger
  use Mix.Task
  @requirements ["app.config"]

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

  @impl Mix.Task
  def run([chunk_size]) do
    start_repo()
    {chunk_size, ""} = chunk_size |> Integer.parse()

    :filelib.fold_files(
      "thumbnails",
      ".*",
      false,
      fn thumbnail_path, state ->
        [_, ytid] = thumbnail_path |> String.split("/")

        # Thumbnail.fetch does not need to do TTL checks (on purpose, as we can serve the same thumb
        # but maybe not the same link or subtitle),
        # so a direct fetch() will match db behavior exactly.

        metadata? = Thumbnail.fetch(ytid)

        deleted_count =
          if metadata? == nil do
            Logger.info("thumbnail #{ytid} does not exist in db, removing")
            File.rm(thumbnail_path)
            1
          else
            0
          end

        new_state = %{
          filecount: state.filecount + 1,
          deleted_count: state.deleted_count + deleted_count
        }

        if rem(state.filecount, chunk_size) == 0 do
          Logger.info("waiting 20 seconds before next chunk... (state=#{inspect(new_state)})")
          :timer.sleep(20000)
        end

        new_state
      end,
      %{filecount: 0, deleted_count: 0}
    )
    |> then(fn state ->
      Logger.info("done processing #{state.filecount} files")
    end)

    Logger.info("done!")
  end
end

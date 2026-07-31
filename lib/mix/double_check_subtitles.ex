defmodule Mix.Tasks.YtSearch.DoubleCheckSubtitles do
  import Ecto.Query
  alias YtSearch.Data.SubtitleRepo
  alias YtSearch.Subtitle
  require Logger
  use Mix.Task
  @requirements ["app.config"]

  @shortdoc "find subtitle files on disk that have no db row (dry-run by default, --prune deletes)"

  @progress_interval 1000

  def start_repo do
    [:ecto, :ecto_sql, :exqlite, :db_connection, :logger]
    |> Enum.each(fn app -> Application.ensure_all_started(app) end)

    children = [
      YtSearch.Data.SubtitleRepo
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: YtSearch.Supervisor
    )
  end

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [prune: :boolean])
    prune? = opts[:prune] || false

    start_repo()

    # youtube ids may contain underscores, so filenames like "abc_def_en"
    # can't be split back into {youtube_id, language} unambiguously.
    # instead, precompute every valid filename from the db side.
    known_ids =
      from(s in Subtitle, select: {s.youtube_id, s.language})
      |> SubtitleRepo.all()
      |> Enum.map(fn {youtube_id, language} -> "#{youtube_id}_#{language}" end)
      |> MapSet.new()

    Logger.info("#{MapSet.size(known_ids)} subtitles in db")

    files =
      case File.ls("subtitles") do
        {:ok, files} -> files
        {:error, :enoent} -> Mix.raise("subtitles directory not found in #{File.cwd!()}")
      end

    total = length(files)
    mode = if prune?, do: "prune", else: "dry-run"
    Logger.info("#{total} files to check (#{mode})")

    state =
      files
      |> Enum.reduce(%{checked: 0, orphans: 0, bytes: 0}, fn filename, state ->
        path = Path.join("subtitles", filename)

        state =
          if MapSet.member?(known_ids, filename) do
            state
          else
            handle_orphan(state, path, prune?)
          end

        state = %{state | checked: state.checked + 1}

        if rem(state.checked, @progress_interval) == 0 do
          Logger.info(
            "checked #{state.checked}/#{total} files, orphans so far: #{state.orphans} (#{format_bytes(state.bytes)})"
          )
        end

        state
      end)

    verb = if prune?, do: "reclaimed", else: "reclaimable"

    Logger.info(
      "done! checked #{state.checked} files, #{state.orphans} orphaned subtitles, #{format_bytes(state.bytes)} #{verb}"
    )
  end

  defp handle_orphan(state, path, prune?) do
    size =
      case File.stat(path) do
        {:ok, %{size: size}} -> size
        {:error, _} -> 0
      end

    if prune? do
      File.rm!(path)
    end

    %{state | orphans: state.orphans + 1, bytes: state.bytes + size}
  end

  defp format_bytes(bytes) when bytes >= 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GiB"

  defp format_bytes(bytes) when bytes >= 1024 * 1024,
    do: "#{Float.round(bytes / (1024 * 1024), 2)} MiB"

  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 2)} KiB"
  defp format_bytes(bytes), do: "#{bytes} B"
end

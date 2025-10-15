defmodule YtSearch.Thumbnail.Atlas do
  require Logger

  alias YtSearch.Thumbnail
  alias YtSearch.SearchSlot

  defmodule InvalidRatio do
    use Prometheus.Metric

    def setup() do
      Histogram.declare(
        name: :yts_thumbnail_atlas_invalid_ratio,
        help: "Ratio of invalid thumbnails in atlas requests (0-1 range)",
        buckets: [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
      )

      Counter.declare(
        name: :yts_thumbnail_atlas_errors,
        help: "Invalid thumbnails in atlas assembly",
        labels: [:reason]
      )
    end

    def observe(invalid_count, total_count) when total_count > 0 do
      ratio = invalid_count / total_count

      Histogram.observe(
        [name: :yts_thumbnail_atlas_invalid_ratio],
        ratio
      )
    end

    def observe(_invalid_count, 0), do: :ok

    def inc_error(reason) do
      Counter.inc(
        name: :yts_thumbnail_atlas_errors,
        labels: [to_string(reason)]
      )
    end
  end

  @spec assemble(String.t()) ::
          {:ok, String.t(), binary()} | {:error, :unknown_search_slot}
  def assemble(search_slot_id) do
    case SearchSlot.fetch(search_slot_id) do
      nil ->
        {:error, :unknown_search_slot}

      search_slot ->
        do_assemble(search_slot)
    end
  end

  @invalid_thumbnail_path Path.join(:code.priv_dir(:yt_search), "static/invalid_thumbnail.png")

  defp montage,
    do: Application.fetch_env!(:yt_search, YtSearch.ThumbnailAtlas)[:montage_command]

  def assemble_one(slot) do
    [slot]
    |> internal_assemble
  end

  def do_assemble(search_slot) do
    search_slot
    |> SearchSlot.fetched_slots_from_search()
    |> internal_assemble()
  end

  defp internal_assemble(slots) do
    thumbnail_paths =
      slots
      |> Enum.map(fn slot ->
        # for each slot, attach to its thumbnail mutex, so if
        # theres thumbnails still being downloaded, we wait for
        # them all before assembling atlas

        if slot != nil do
          Mutex.under(ThumbnailMutex, slot.youtube_id, fn ->
            thumb =
              slot.youtube_id
              |> Thumbnail.fetch()

            if thumb != nil do
              {
                thumb.id |> Thumbnail.path_for(),
                thumb |> Thumbnail.stat()
              }
            else
              InvalidRatio.inc_error(:missing_thumbnail)
              nil
            end
          end)
        else
          InvalidRatio.inc_error(:missing_slot)
          nil
        end
      end)
      |> Enum.map(fn
        nil ->
          @invalid_thumbnail_path

        # file doesn't exist (enoent)
        {_, nil} ->
          InvalidRatio.inc_error(:file_not_found)
          @invalid_thumbnail_path

        {path, stat} ->
          case stat.size do
            0 ->
              InvalidRatio.inc_error(:zero_size)
              @invalid_thumbnail_path

            _ ->
              path
          end
      end)

    # Track invalid thumbnail ratio metric
    total_count = length(thumbnail_paths)
    invalid_count = Enum.count(thumbnail_paths, fn path -> path == @invalid_thumbnail_path end)
    InvalidRatio.observe(invalid_count, total_count)

    atlas_image_path = Temp.path!() <> ".png"

    # elixir-mogrify does not support append mode or whatever, use montage directly instead
    # https://superuser.com/questions/290656/vertically-stack-multiple-images-using-imagemagick

    args =
      thumbnail_paths ++
        ["-tile", "8x4", "-depth", "8", "-geometry", "128x128!", "-background", "none"] ++
        [atlas_image_path]

    Logger.debug("calling #{montage()} with args #{inspect(args)}")

    {output, exit_code} =
      System.cmd(
        montage(),
        args,
        stderr_to_stdout: true
      )

    Logger.debug("montage output: #{inspect(output)}")

    if exit_code != 0 do
      Logger.error("failed to run #{montage()}. #{exit_code}. #{inspect(output)}")
    end

    0 = exit_code

    # read first since we have to delete the atlas later
    result = {:ok, "image/png", File.read!(atlas_image_path)}

    case File.rm(atlas_image_path) do
      :ok ->
        nil

      error ->
        Logger.error("failed to delete atlas #{atlas_image_path}: #{inspect(error)}, ignoring")
    end

    result
  end
end

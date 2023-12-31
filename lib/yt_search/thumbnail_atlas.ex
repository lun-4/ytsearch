defmodule YtSearch.Thumbnail.Atlas do
  require Logger

  alias YtSearch.Thumbnail
  alias YtSearch.SearchSlot

  @spec assemble(String.t()) ::
          {:ok, String.t(), binary()} | {:error, :unknown_search_slot}
  def assemble(search_slot_id) do
    case SearchSlot.fetch_by_id(search_slot_id) do
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
            slot.youtube_id
            |> Thumbnail.fetch()
            |> Thumbnail.blob()
          end)
        else
          nil
        end
      end)
      |> Enum.map(fn maybe_thumbnail ->
        case maybe_thumbnail do
          nil ->
            @invalid_thumbnail_path

          "" ->
            @invalid_thumbnail_path

          data ->
            temporary_path = Temp.path!()
            File.write!(temporary_path, data)
            temporary_path
        end
      end)

    atlas_image_path = Temp.path!() <> ".png"

    # elixir-mogrify does not support append mode or whatever, use montage directly instead
    # https://superuser.com/questions/290656/vertically-stack-multiple-images-using-imagemagick

    used_paths = thumbnail_paths ++ [atlas_image_path]

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

    result = {:ok, "image/png", File.read!(atlas_image_path)}

    # clean everything up afterwards
    used_paths
    |> Enum.filter(fn path -> path != @invalid_thumbnail_path end)
    |> Enum.each(fn path ->
      case File.rm(path) do
        :ok ->
          nil

        error ->
          Logger.error("failed to delete #{path}: #{inspect(error)}, ignoring")
      end
    end)

    result
  end
end

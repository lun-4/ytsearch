defmodule YtSearch.Thumbnail.Atlas do
  require Logger

  alias YtSearch.Thumbnail
  alias YtSearch.SearchSlot
  alias YtSearch.Slot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias Mogrify.Draw

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

  @atlas_size 512
  @invalid_thumbnail_path "priv/static/invalid_thumbnail.png"

  def do_assemble(search_slot) do
    thumbnail_paths =
      search_slot
      |> SearchSlot.get_slots()
      |> Enum.map(fn entry ->
        case entry do
          ["channel", slot_id] ->
            ChannelSlot.fetch(slot_id)

          ["playlist", slot_id] ->
            PlaylistSlot.fetch(slot_id)

          [typ, slot_id] when typ in ["video", "short", "livestream"] ->
            Slot.fetch_by_id(slot_id)

          _ ->
            raise "invalid type for entry: #{inspect(entry)}"
        end
      end)
      |> Enum.map(fn slot ->
        # for each slot, attach to its thumbnail mutex, so if
        # theres thumbnails still being downloaded, we wait for
        # them all before assembling atlas

        if slot != nil do
          Mutex.under(ThumbnailMutex, slot.youtube_id, fn ->
            Thumbnail.fetch(slot.youtube_id)
          end)
        else
          nil
        end
      end)
      |> Enum.map(fn maybe_thumbnail ->
        case maybe_thumbnail do
          nil ->
            # give it blank image
            #
            # TODO use util method to get priv/static
            # instead of relying on CWD
            @invalid_thumbnail_path

          thumbnail ->
            temporary_path = Temp.path!()
            File.write!(temporary_path, thumbnail.data)
            temporary_path
        end
      end)

    atlas_image_path = Temp.path!() <> ".png"

    # elixir-mogrify does not support  append mode or whatever, use montage
    # directly
    # https://superuser.com/questions/290656/vertically-stack-multiple-images-using-imagemagick

    paths_to_montage = thumbnail_paths ++ [atlas_image_path]

    {_, 0} =
      System.cmd(
        "montage",
        ["-tile", "8x4", "-geometry", "128x128!", "-background", "#000000"] ++
          paths_to_montage,
        stderr_to_stdout: true
      )

    result = {:ok, "image/png", File.read!(atlas_image_path)}

    # clean everything up afterwards
    paths_to_montage
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

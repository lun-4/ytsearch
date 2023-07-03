defmodule YtSearch.Thumbnail.Atlas do
  require Logger

  alias YtSearch.Thumbnail
  alias YtSearch.SearchSlot
  alias YtSearch.Slot
  alias YtSearch.ChannelSlot
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

  def do_assemble(search_slot) do
    thumbnail_paths =
      search_slot
      |> SearchSlot.get_slots()
      |> Enum.map(fn entry ->
        case entry do
          ["channel", slot_id] ->
            ChannelSlot.fetch(slot_id)

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

        Mutex.under(ThumbnailMutex, slot.youtube_id, fn ->
          Thumbnail.fetch(slot.youtube_id)
        end)
      end)
      |> Enum.map(fn maybe_thumbnail ->
        case maybe_thumbnail do
          nil ->
            # give it blank image

            # TODO use util method to get priv/static
            # instead of relying on CWD
            "priv/static/invalid_thumbnail.png"

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

    {_, 0} =
      System.cmd(
        "montage",
        ["-tile", "4x4", "-geometry", "128x128!", "-background", "#000000"] ++
          thumbnail_paths ++ [atlas_image_path]
      )

    {:ok, "image/png", File.read!(atlas_image_path)}
  end
end
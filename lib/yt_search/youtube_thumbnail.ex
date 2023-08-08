defmodule YtSearch.Youtube.Thumbnail do
  require Logger

  alias YtSearch.Thumbnail

  defmodule ThumbnailMetadata do
    @derive Jason.Encoder
    defstruct [:aspect_ratio]
  end

  def fetch_in_background(entity_type, ytdlp_data) do
    # TODO better algorithm for thumbnail selection
    if ytdlp_data["thumbnails"] != nil do
      selected_thumbnail_metadata =
        ytdlp_data["thumbnails"]
        |> Enum.at(0)

      # TODO supervisor?
      spawn(fn ->
        maybe_download_thumbnail(ytdlp_data["id"], selected_thumbnail_metadata["url"])
      end)

      %ThumbnailMetadata{
        aspect_ratio: selected_thumbnail_metadata["width"] / selected_thumbnail_metadata["height"]
      }
    else
      Logger.warning("id '#{ytdlp_data["id"]}' does not provide thumbnail")
      nil
    end
  end

  def fetch_piped_in_background(youtube_id, data) do
    unless data["thumbnail"] == nil do
      # TODO wrap up in a supervisor?
      # reasons for that: handle network failures
      # reasons against: moar codes, also need to fast fail after some amnt of retries
      spawn(fn ->
        maybe_download_thumbnail(youtube_id, data["thumbnail"])
      end)

      %ThumbnailMetadata{
        # 16x9 faking happens here (TODO alpha on the atlas composite for the faking to happen)
        aspect_ratio: 1.77
      }
    else
      Logger.warning("id '#{youtube_id}' does not provide thumbnail")
      nil
    end
  end

  # same idea as Mp4Link.maybe_fetch_upstream

  @spec maybe_download_thumbnail(String.t(), String.t()) :: Thumbnail.t()
  def maybe_download_thumbnail(id, url) do
    case Thumbnail.fetch(id) do
      nil ->
        mutexed_download_thumbnail(id, url)

      thumb ->
        thumb
    end
  end

  def mutexed_download_thumbnail(id, url) do
    Mutex.under(ThumbnailMutex, id, fn ->
      # refetch to prevent double fetch
      case Thumbnail.fetch(id) do
        nil ->
          do_download_thumbnail(id, url)

        thumb ->
          thumb
      end
    end)
  end

  @thumbnail_size 128

  defp do_download_thumbnail(youtube_id, url) do
    Logger.debug("thumbnail requesting #{url}")

    # youtube channels give urls without scheme for some reason
    response =
      if String.starts_with?(url, "//") do
        "https:#{url}"
      else
        url
      end
      |> HTTPoison.get!()

    if response.status_code == 200 do
      content_type = response.headers[:"content-type"]
      body = response.body

      temporary_path = Temp.path!()
      File.write(temporary_path, body)

      # turn the thumbnail into a 16:9 aspect ratio image
      # while adding transparency around the borders for non-16:9 images

      # this lets the world use that transparency to show the correct
      # perceived ratio on the user's eyes

      Mogrify.open(temporary_path)
      |> Mogrify.resize("256x144")
      |> Mogrify.gravity("center")
      |> Mogrify.custom("background", "none")
      |> Mogrify.extent("256x144")
      |> Mogrify.save(in_place: true)

      final_body = File.read!(temporary_path)
      File.rm(temporary_path)
      {:ok, Thumbnail.insert(youtube_id, content_type, final_body)}
    else
      Logger.error(
        "thumbnail request. expected 200, got #{inspect(response.status_code)} #{inspect(response.body)}"
      )

      {:error, {:http_response, response.status_code, response.headers, response.body}}
    end
  end
end

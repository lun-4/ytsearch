defmodule YtSearch.Youtube.Thumbnail do
  require Logger

  alias YtSearch.Thumbnail

  defmodule ThumbnailMetadata do
    @derive Jason.Encoder
    defstruct [:aspect_ratio]
  end

  def fetch_in_background(ytdlp_data) do
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
      Logger.warning("id #{ytdlp_data["id"]} does not provide thumbnail")
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

    {:ok, response} =
      Finch.build(
        :get,
        # youtube channels give urls without scheme for some reason
        if String.starts_with?(url, "//") do
          "https:#{url}"
        else
          url
        end
      )
      |> Finch.request(YtSearch.Finch)

    if response.status == 200 do
      content_type = response.headers[:"content-type"]
      body = response.body

      temporary_path = Temp.path!()
      File.write(temporary_path, body)

      # resize to 128x before storage
      Mogrify.open(temporary_path)
      |> Mogrify.resize("#{@thumbnail_size}x#{@thumbnail_size}!")
      |> Mogrify.save(in_place: true)

      final_body = File.read!(temporary_path)
      {:ok, Thumbnail.insert(youtube_id, content_type, final_body)}
    else
      Logger.error(
        "thumbnail request. expected 200, got #{inspect(response.status)} #{inspect(response.body)}"
      )

      {:error, {:http_response, response.status, response.headers, response.body}}
    end
  end
end

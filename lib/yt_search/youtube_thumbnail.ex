defmodule YtSearch.Youtube.Thumbnail do
  require Logger

  alias YtSearch.Thumbnail

  defmodule ThumbnailMetadata do
    @derive Jason.Encoder
    defstruct [:aspect_ratio]
  end

  def fetch_piped_in_background(youtube_id, data) do
    if data["thumbnail"] != nil do
      # TODO wrap up in a supervisor?
      # reasons for that: handle network failures
      # reasons against: moar codes, also need to fast fail after some amnt of retries
      Task.Supervisor.async(YtSearch.ThumbnailSupervisor, fn ->
        maybe_download_thumbnail(
          youtube_id,
          data["thumbnail"] |> YtSearch.Youtube.unproxied_piped_url()
        )
      end)

      # NOTE: this is a fake ratio because we now do 1:1 ratio with alpha on atlas
      # UPGRADE: aspect_ratio is not used on /a/2
      %ThumbnailMetadata{
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

  defp do_download_thumbnail(youtube_id, url) do
    Logger.debug("thumbnail requesting #{url}")

    # youtube channels give urls without scheme for some reason
    {:ok, response} =
      if String.starts_with?(url, "//") do
        "https:#{url}"
      else
        url
      end
      |> Tesla.get()

    if response.status == 200 do
      content_type = Tesla.get_header(response, "content-type")
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
        "thumbnail request. expected 200, got #{inspect(response.status)} #{inspect(response.body)}"
      )

      {:error, {:http_response, response.status, response.headers, response.body}}
    end
  end
end

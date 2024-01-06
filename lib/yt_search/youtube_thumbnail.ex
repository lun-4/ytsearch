defmodule YtSearch.Youtube.Thumbnail do
  require Logger

  alias YtSearch.SlotUtilities
  alias YtSearch.Thumbnail

  defmodule ThumbnailMetadata do
    @derive Jason.Encoder
    defstruct [:aspect_ratio]
  end

  def fetch_piped_in_background(youtube_id, data, opts) do
    if data["thumbnail"] != nil do
      Task.Supervisor.async(YtSearch.ThumbnailSupervisor, fn ->
        maybe_download_thumbnail(
          youtube_id,
          data["thumbnail"] |> YtSearch.Youtube.unproxied_piped_url(),
          opts
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

  @spec maybe_download_thumbnail(String.t(), String.t(), Keyword.t()) :: Thumbnail.t()
  def maybe_download_thumbnail(id, url, opts) do
    maybe_metadata = Thumbnail.fetch(id)

    maybe_filesize =
      Thumbnail.path_for(id)
      |> File.stat()
      |> then(fn
        {:ok, %{size: size}} -> size
        {:error, :enoent} -> 0
        {:error, :_} -> 0
      end)

    should_download? = maybe_metadata == nil or maybe_filesize == 0

    if should_download? do
      mutexed_download_thumbnail(id, url, opts)
    else
      maybe_metadata
      |> SlotUtilities.refresh_expiration(opts)
    end
  end

  def mutexed_download_thumbnail(id, url, opts) do
    Mutex.under(ThumbnailMutex, id, fn ->
      # refetch to prevent double fetch
      case Thumbnail.fetch(id) do
        nil ->
          do_download_thumbnail(id, url, opts)

        thumb ->
          thumb
      end
    end)
  end

  @mogrify false

  defp do_download_thumbnail(youtube_id, url, opts) do
    if youtube_id |> Thumbnail.path_for() |> File.exists?() do
      # if it already exists, insert the metadata entry (as to be in this function,
      # the db entry would be currently missing)
      {:ok, Thumbnail.insert(youtube_id, "image/webp", opts)}
    else
      really_do_download_thumbnail(youtube_id, url, opts)
    end
  end

  defp really_do_download_thumbnail(youtube_id, url, opts) do
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

      # turn the thumbnail into a 16:9 aspect ratio image
      # while adding transparency around the borders for non-16:9 images

      # this lets the world use that transparency to show the correct
      # perceived ratio on the user's eyes

      if @mogrify do
        temporary_path = Temp.path!()
        File.write(temporary_path, body)

        Mogrify.open(temporary_path)
        |> Mogrify.resize("256x144")
        |> Mogrify.gravity("center")
        |> Mogrify.custom("background", "none")
        |> Mogrify.extent("256x144")
        |> Mogrify.save(in_place: true)

        final_body = File.read!(temporary_path)
        File.rm(temporary_path)
        {:ok, Thumbnail.insert(youtube_id, content_type, final_body, opts)}
      else
        input_image = Image.from_binary!(body)

        input_image
        |> Image.add_alpha(:transparent)
        |> then(fn
          {:ok, image} ->
            image

          {:error, "Image already has an alpha band"} ->
            input_image

          {:error, err} ->
            raise err
        end)
        |> Image.thumbnail!(256, height: 144)
        |> Image.embed!(256, 144, background_transparency: 0, x: :center, y: :center)
        |> Image.write!(
          youtube_id
          |> Thumbnail.path_for()
          |> File.stream!(),
          suffix: ".webp"
        )

        {:ok, Thumbnail.insert(youtube_id, content_type, opts)}
      end
    else
      Logger.error(
        "thumbnail request. expected 200, got #{inspect(response.status)} #{inspect(response.body)}"
      )

      {:error, {:http_response, response.status, response.headers, response.body}}
    end
  end
end

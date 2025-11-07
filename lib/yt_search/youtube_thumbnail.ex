defmodule YtSearch.Youtube.Thumbnail do
  require Logger

  alias YtSearch.SlotUtilities
  alias YtSearch.Thumbnail

  defmodule TaskCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_thumbnail_task_results,
        help: "Thumbnail task results",
        labels: [:status]
      )

      Counter.declare(
        name: :yts_thumbnail_task_total,
        help: "Thumbnail tasks"
      )

      Counter.declare(
        name: :yts_thumbnail_task_spawns,
        help: "Thumbnail task spawns"
      )

      Counter.declare(
        name: :yts_thumbnail_task_checks,
        help: "Thumbnail task checks"
      )

      Counter.declare(
        name: :yts_thumbnail_task_execs,
        help: "Thumbnail task execs"
      )

      Counter.declare(
        name: :yts_thumbnail_task_finish,
        help: "Thumbnail task finishs"
      )

      Counter.declare(
        name: :yts_thumbnail_task_inner_checks,
        help: "Thumbnail task inner checks"
      )

      Counter.declare(
        name: :yts_thumbnail_task_inner_downloads,
        help: "Thumbnail task inner downloads"
      )

      Counter.declare(
        name: :yts_thumbnail_task_inner_inner_downloads,
        help: "Thumbnail task inner inner downloads"
      )
    end

    def inc(status) do
      Counter.inc(name: :yts_thumbnail_task_total)

      Counter.inc(
        name: :yts_thumbnail_task_results,
        labels: [to_string(status)]
      )
    end

    def inc_check() do
      Counter.inc(name: :yts_thumbnail_task_checks)
    end

    def inc_spawn() do
      Counter.inc(name: :yts_thumbnail_task_spawns)
    end

    def inc_exec() do
      Counter.inc(name: :yts_thumbnail_task_execs)
    end

    def inc_finish() do
      Counter.inc(name: :yts_thumbnail_task_finish)
    end

    def inc_inner_check() do
      Counter.inc(name: :yts_thumbnail_task_inner_checks)
    end

    def inc_inner_download() do
      Counter.inc(name: :yts_thumbnail_task_inner_downloads)
    end

    def inc_inner_inner_download() do
      Counter.inc(name: :yts_thumbnail_task_inner_inner_downloads)
    end
  end

  defmodule ThumbnailMetadata do
    @derive Jason.Encoder
    defstruct [:aspect_ratio]
  end

  def fetch_piped_in_background(youtube_id, data, opts) do
    TaskCounter.inc_check()

    if data["thumbnail"] != nil do
      TaskCounter.inc_spawn()

      task =
        Task.Supervisor.async(YtSearch.ThumbnailSupervisor, fn ->
          TaskCounter.inc_exec()

          try do
            maybe_download_thumbnail(
              youtube_id,
              data["thumbnail"] |> YtSearch.Youtube.unproxied_piped_url(),
              opts
            )
          after
            TaskCounter.inc_finish()
            # Clean up task ref when done
            :ets.delete(:thumbnail_tasks, youtube_id)
          end
        end)

      # Store task PID so atlas can await it (store PID not Task struct to allow cross-process monitoring)
      :ets.insert(:thumbnail_tasks, {youtube_id, task.pid})

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

  defp filesize_for(id) do
    Thumbnail.path_for(id)
    |> File.stat()
    |> then(fn
      {:ok, %{size: size}} -> size
      {:error, :enoent} -> 0
      {:error, :_} -> 0
    end)
  end

  @spec maybe_download_thumbnail(String.t(), String.t(), Keyword.t()) :: Thumbnail.t()
  def maybe_download_thumbnail(id, url, opts) do
    TaskCounter.inc_inner_check()
    maybe_metadata = Thumbnail.fetch(id)
    maybe_filesize = filesize_for(id)
    should_download? = maybe_metadata == nil or maybe_filesize == 0

    if should_download? do
      mutexed_download_thumbnail(id, url, opts)
    else
      maybe_metadata
      |> SlotUtilities.refresh_expiration(opts)
    end
  end

  def mutexed_download_thumbnail(id, url, opts) do
    start_ts = System.monotonic_time(:millisecond)

    Mutex.under(ThumbnailMutex, id, fn ->
      end_ts = System.monotonic_time(:millisecond)
      latency = end_ts - start_ts
      YtSearch.MetadataExtractor.Worker.TaskLatency.register(:thumbnail_mutex, latency)

      TaskCounter.inc_inner_download()
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
    TaskCounter.inc_inner_inner_download()

    if filesize_for(youtube_id) > 0 do
      # if it already exists, insert the metadata entry (as to be in this function,
      # the db entry would be currently missing)
      TaskCounter.inc(:cache_skip)
      {:ok, Thumbnail.insert(youtube_id, "image/webp", opts)}
    else
      YtSearch.MetadataExtractor.Worker.TaskLatency.register(:thumbnail, fn ->
        try do
          result = really_do_download_thumbnail(youtube_id, url, opts)

          case result do
            {:ok, _} -> TaskCounter.inc(:success)
            {:error, {:http_response, status, _, _}} -> TaskCounter.inc("error_http_#{status}")
            {:error, _} -> TaskCounter.inc(:error_other)
          end

          result
        rescue
          e ->
            Logger.error(Exception.format(:error, e, __STACKTRACE__))
            TaskCounter.inc(:exception)
            reraise e, __STACKTRACE__
        end
      end)
    end
  end

  defp target_dimensions(x, y) do
    tx = x / 1.77777777777

    if tx < y do
      sf = y / 128
      new_x = tx / sf
      {new_x |> round, 128}
    else
      sf = tx / 128
      new_y = y / sf
      {128, new_y |> round}
    end
  end

  defp really_do_download_thumbnail(youtube_id, url, opts) do
    Logger.debug("thumbnail requesting #{url}")

    # youtube channels give urls without scheme for some reason
    {:ok, response} =
      YtSearch.MetadataExtractor.Worker.TaskLatency.register(:thumbnail_download, fn ->
        if String.starts_with?(url, "//") do
          "https:#{url}"
        else
          url
        end
        |> Tesla.get()
      end)

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

        {image_width, image_height} = {
          input_image |> Image.width(),
          input_image |> Image.height()
        }

        {target_width, target_height} = target_dimensions(image_width, image_height)

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
        |> Image.thumbnail!(target_width, height: target_height, resize: :force)
        |> Image.embed!(128, 128, background_transparency: 0, x: :center, y: :center)
        |> Image.write!(
          youtube_id
          |> Thumbnail.path_for()
          |> File.stream!(),
          # use lossless webp as an exchange in storage vs unecessary CPU time
          suffix: ".webp",
          effort: 1
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

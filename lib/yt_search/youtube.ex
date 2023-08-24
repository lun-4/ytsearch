defmodule YtSearch.Youtube do
  require Logger
  alias YtSearch.Youtube.Ratelimit
  alias YtSearch.Youtube.Latency
  alias YtSearch.Piped
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot

  defp piped() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:piped_url]
  end

  defmodule CallCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_ytdlp_call_count,
        help: "Total times we requested the ytdlp path for calling ytdlp",
        labels: [:type]
      )
    end

    def inc(type) do
      Counter.inc(
        name: :yts_ytdlp_call_count,
        labels: [to_string(type)]
      )
    end
  end

  # vrcjson does not support unbalanced braces inside strings
  # this has been reported to vrchat already
  #
  # https://feedback.vrchat.com/vrchat-udon-closed-alpha-bugs/p/braces-inside-strings-in-vrcjson-can-fail-to-deserialize
  #
  # workaround for now is to strip off any brace character. we could write a balancer and strip
  # off the edge case, but i dont think i care enough to do that just for vrchat.

  defp vrcjson_workaround(incoming_data) do
    case incoming_data do
      data when is_map(data) ->
        data
        |> Map.keys()
        |> Enum.map(fn key ->
          value =
            case Map.get(data, key) do
              v when is_bitstring(v) ->
                v
                |> String.replace(~r/[\[\]{}]/, "")
                |> String.trim(" ")

              any ->
                any
            end

          {key, value}
        end)
        |> Map.new()

      data when is_list(data) ->
        data
        |> Enum.map(&vrcjson_workaround/1)
    end
  end

  def videos_for(%ChannelSlot{youtube_id: channel_id}) do
    piped_search_call(&Piped.channel/2, channel_id, "relatedStreams")
  end

  def videos_for(%PlaylistSlot{youtube_id: playlist_id}) do
    piped_search_call(&Piped.playlists/2, playlist_id, "relatedStreams")
  end

  @youtube_url_regex ~r/(www\.youtube\.com|youtube\.com|youtu\.be)\/(.+)$/
  @host_by_watch_query ["www.youtube.com", "youtube.com"]
  @host_by_path ["youtu.be"]

  @keys_to_copy [
    "title",
    "uploader",
    "uploaderUrl",
    "isShort",
    "duration",
    "views",
    {"uploader", "uploaderName"},
    {"description", "shortDescription"},
    {"thumbnailUrl", "thumbnail"}
  ]

  def videos_for(text) when is_bitstring(text) do
    captures = Regex.run(@youtube_url_regex, text)

    unless captures == nil do
      [_full, host, url_path] = captures

      with {:ok, youtube_id} <- youtube_id_from_uri(host, url_path),
           {:ok, piped_response} <-
             piped_call(:search_url, &Piped.streams/2, youtube_id, nil) do
        video_result =
          @keys_to_copy
          |> Enum.reduce(%{}, fn key, result ->
            {key_from, key_to} =
              case key do
                {_, _} -> key
                key -> {key, key}
              end

            result
            |> Map.put(key_to, piped_response[key_from])
          end)
          # NOTE isShort is not shown on stream output. we will show results as type=video
          # NOTE duration is 0, not -1, for live streams
          |> Map.put("type", "stream")
          |> Map.put("url", "/watch?v=#{youtube_id}")
          # we don't get the real uploaded timestamp, so fill it with date at midnight
          |> Map.put(
            "uploaded",
            piped_response["uploadDate"]
            |> Date.from_iso8601!()
            |> DateTime.new!(~T[00:00:00])
            |> DateTime.to_unix(:millisecond)
          )

        {:ok, [video_result]}
      end
    else
      case Ratelimit.for_text_search() do
        :allow ->
          piped_search_call(&Piped.search/2, text, "items")

        :deny ->
          {:error, :overloaded_ytdlp_seats}
      end
    end
  end

  defp youtube_id_from_uri(host, url_path) do
    cond do
      host in @host_by_watch_query ->
        uri = URI.parse(url_path)

        unless uri.query == nil do
          query =
            uri.query
            |> URI.decode_query()

          {:ok, query["v"]}
        else
          {:input_error, :invalid_format}
        end

      host in @host_by_path ->
        video_id = url_path |> String.split("/") |> Enum.at(0)
        {:ok, video_id}

      true ->
        Logger.error("invalid host: #{host}")
        {:input_error, :invalid_host}
    end
  end

  defp piped_search_call(func, id, list_field) do
    piped_call(:search, func, id, list_field, limit: 20)
  end

  defp piped_call(call_type, func, id, list_field, opts \\ []) do
    CallCounter.inc(call_type)

    start_ts = System.monotonic_time(:millisecond)
    result = func.(piped(), id)
    end_ts = System.monotonic_time(:millisecond)
    Latency.register(call_type, end_ts - start_ts)

    case result do
      {:ok, %{status: 200} = response} ->
        {:ok,
         response.body
         |> then(fn body ->
           limit = Keyword.get(opts, :limit)

           result =
             unless list_field == nil do
               body[list_field]
             else
               body
             end

           if is_list(result) and limit != nil do
             result |> Enum.slice(0, limit)
           else
             result
           end
         end)
         |> vrcjson_workaround}

      {:ok, %{status: 500, body: raw_body} = response} ->
        body =
          case raw_body
               |> then(fn body ->
                 case body do
                   {:ok, body} -> body |> Jason.decode()
                   v -> {:ok, v}
                 end
               end) do
            {:ok, body} ->
              body

            {:error, _} = val ->
              Logger.error(
                "an error happened while parsing 500, #{inspect(val)}, #{inspect(raw_body)}"
              )

              %{"message" => ""}
          end

        message = body["message"] || ""

        cond do
          String.contains?(message, "Video unavailable") ->
            Logger.warning("this is an unavailable youtube id")
            {:error, :video_unavailable}

          String.contains?(message, "This channel does not exist") ->
            Logger.warning("this is a non existing channel")
            {:error, :channel_not_found}

          String.contains?(message, "This video is only available to Music Premium members") ->
            Logger.warning("This video is only available to Music Premium members")
            {:error, :video_unavailable}

          String.contains?(message, "This channel is not available") ->
            Logger.warning("this is an unavailable channel")
            {:error, :channel_unavailable}

          true ->
            {:error, response}
        end

      {:ok, %Tesla.Env{} = response} ->
        {:error, response}

      {:error, _} = error_value ->
        error_value
    end
  end

  def trending(region \\ "US") do
    piped_call(:search, &Piped.trending/2, region, nil, limit: 20)
  end

  def extract_valid_streams(incoming_video_streams) do
    video_streams =
      incoming_video_streams
      |> Enum.map(fn stream ->
        # for some reason, piped does not expose width/height when videoOnly=true
        # extrapolate when that's the case

        if stream["height"] == 0 or stream["width"] == 0 do
          case stream["quality"] do
            "720p" ->
              stream
              |> Map.put("width", 1280)
              |> Map.put("height", 720)

            "360p" ->
              stream
              |> Map.put("width", 480)
              |> Map.put("height", 360)

            "480p" ->
              stream
              |> Map.put("width", 640)
              |> Map.put("height", 480)

            "240p" ->
              stream
              |> Map.put("width", 320)
              |> Map.put("height", 240)

            "144p" ->
              stream
              |> Map.put("width", 256)
              |> Map.put("height", 144)

            _ ->
              stream
          end
        else
          stream
        end
      end)

    # wanted format selection in ytdlp format:
    # mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]
    # we translate it into two Enum.filter calls, preffering first filter

    first_filter_results =
      video_streams
      |> Enum.filter(fn stream ->
        stream["mimeType"] == "video/mp4" and
          stream["height"] <= 1080 and
          stream["height"] >= 64 and
          stream["width"] >= 64 and
          not stream["videoOnly"]
      end)
      # order by pixel amount
      |> Enum.sort_by(fn stream -> stream["width"] * stream["height"] end, :desc)

    second_filter_results =
      video_streams
      |> Enum.filter(fn stream ->
        stream["height"] <= 1080 and
          stream["height"] >= 64 and
          stream["width"] >= 64 and
          not stream["videoOnly"]
      end)
      |> Enum.sort_by(fn stream -> stream["width"] * stream["height"] end, :desc)

    first_filter_results |> Enum.at(0) || second_filter_results |> Enum.at(0)
  end

  defp expiry_from_query(uri) do
    if uri.query == nil do
      nil
    else
      uri.query
      |> URI.decode_query()
      |> Map.get("expire")
      |> then(fn maybe_expiry ->
        if maybe_expiry == nil do
          nil
        else
          {value, ""} = Integer.parse(maybe_expiry)
          value
        end
      end)
    end
  end

  defp expiry_from_path(uri) do
    maybe_expiry_value =
      uri.path
      |> then(fn path ->
        if path == nil do
          ""
        else
          path
        end
      end)
      |> String.split("/")
      |> Enum.at(5)

    if maybe_expiry_value == nil do
      nil
    else
      case Integer.parse(maybe_expiry_value) do
        :error -> nil
        {expiry, _anything} -> expiry
      end
    end
  end

  def unproxied_piped_url(url) when is_bitstring(url) do
    url
    |> URI.parse()
    |> unproxied_piped_url
  end

  def unproxied_piped_url(%URI{} = uri) do
    query = (uri.query || "") |> URI.decode_query()
    host = query["host"] || uri.host

    uri
    |> Map.put(:host, host)
    |> Map.put(:authority, host)
    |> to_string
  end

  def expiry_from_uri(uri) do
    expiry_from_query(uri) || expiry_from_path(uri)
  end

  def extract_subtitles(meta) do
    subtitles = meta["subtitles"]

    result =
      subtitles
      |> Enum.map(fn subtitle ->
        # make it akin to ytdlp
        if not subtitle["autoGenerated"] do
          code = subtitle["code"]
          subtitle |> Map.put("code", "#{code}-orig")
        else
          subtitle
        end
      end)
      # prefer english subtitles (we dont have subtitle selection features yet)
      |> Enum.filter(fn subtitle -> String.starts_with?(subtitle["code"], "en") end)
      |> Enum.map(fn subtitle ->
        # map all urls to direct calls, no need to use the piped proxy
        subtitle
        |> Map.put(
          "url",
          subtitle["url"] |> unproxied_piped_url
        )
      end)
      |> Enum.map(fn subtitle ->
        # map each to a task that fetches the subtitle from youtube
        Task.async(fn ->
          url = subtitle["url"]
          Logger.debug("subtitle, calling #{url}")

          case Tesla.get(url) do
            {:ok, %{status: 200} = response} ->
              {subtitle, response.body}

            result ->
              Logger.error("#{url} failed, got #{inspect(result)}")
              nil
          end
        end)
      end)
      |> Enum.map(fn task ->
        Task.await(task)
      end)
      |> Enum.filter(fn result -> result != nil end)

    unless Enum.empty?(result) do
      {:ok, result}
    else
      {:error, :no_valid_subtitles_found}
    end
  end

  def video_metadata(youtube_id) do
    piped_call(:streams, &Piped.streams/2, youtube_id, nil)
  end

  defmodule Latency do
    use Prometheus.Metric

    def setup() do
      Histogram.declare(
        name: :yts_ytdlp_latency,
        help: "latency of certain yt-dlp calls",
        labels: [:call_type],
        buckets:
          [
            10..100//10,
            100..1000//100,
            1000..2000//100,
            2000..4000//500,
            4000..10000//1000,
            10000..20000//1500
          ]
          |> Enum.flat_map(&Enum.to_list/1)
          |> Enum.uniq()
      )
    end

    def register(call_type, latency) do
      Histogram.observe(
        [
          name: :yts_ytdlp_latency,
          labels: [call_type]
        ],
        latency
      )
    end
  end
end

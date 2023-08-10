defmodule YtSearch.Youtube do
  require Logger

  alias YtSearch.Youtube.Ratelimit
  alias YtSearch.Youtube.Latency

  @spec ytdlp() :: String.t()
  defp ytdlp() do
    ytdlp_path = Application.fetch_env!(:yt_search, YtSearch.Youtube)[:ytdlp_path]

    if String.starts_with?(ytdlp_path, "/") do
      ytdlp_path
    else
      # find it manually in path
      {path, _} =
        System.fetch_env!("PATH")
        |> String.split(":")
        |> Enum.map(fn path_directory ->
          joined_path =
            path_directory
            |> Path.join(ytdlp_path)

          {joined_path, File.exists?(joined_path)}
        end)
        |> Enum.filter(fn {_, exists?} -> exists? end)
        |> Enum.at(0)

      path
    end
  end

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

  defp run_ytdlp(call_type, args, opts \\ []) do
    CallCounter.inc(call_type)

    start_ts = System.monotonic_time(:millisecond)

    {status, result} =
      :exec.run(
        [ytdlp()] ++ args,
        [:sync, :stdout, :stderr] ++ opts
      )

    end_ts = System.monotonic_time(:millisecond)
    Latency.register(call_type, end_ts - start_ts)

    stdout = result |> Keyword.get(:stdout) || [""]
    stderr = result |> Keyword.get(:stderr) || [""]

    exit_status =
      case status do
        :ok -> 0
        _ -> result |> Keyword.get(:exit_status)
      end

    {status,
     result
     # i can't trust the library splits exactly at line breaks
     # so i join them back here
     |> Keyword.put(
       :stdout,
       stdout |> Enum.reduce("", fn x, acc -> acc <> x end)
     )
     |> Keyword.put(
       :stderr,
       stderr |> Enum.reduce("", fn x, acc -> acc <> x end)
     )
     |> Keyword.put(:exit_status, exit_status)}
  end

  defp from_result(result) do
    {
      result |> Keyword.get(:stdout),
      result |> Keyword.get(:stderr),
      result |> Keyword.get(:exit_status)
    }
  end

  alias YtSearch.Piped
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot

  def videos_for(%ChannelSlot{youtube_id: channel_id}) do
    piped_search_call(&Piped.channel/2, channel_id, "relatedStreams")
  end

  def videos_for(%PlaylistSlot{youtube_id: playlist_id}) do
    piped_search_call(&Piped.playlists/2, playlist_id, "relatedStreams")
  end

  def videos_for(text) when is_bitstring(text) do
    if String.starts_with?(text, "https://") do
      # TODO maybe do parsing of youtube ids here
      raise "no urls in search"
    end

    case Ratelimit.for_text_search() do
      :allow ->
        piped_search_call(&Piped.search/2, text, "items")

      :deny ->
        {:error, :overloaded_ytdlp_seats}
    end
  end

  defp piped_search_call(func, id, list_field) do
    piped_call(:search, func, id, list_field)
  end

  defp piped_call(call_type, func, id, list_field) do
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
           unless list_field == nil do
             body[list_field]
           else
             body
           end
         end)
         |> vrcjson_workaround}

      {:error, %{status: 500, body: {:ok, raw_body}} = response} ->
        body =
          case raw_body |> Jason.decode() do
            {:ok, body} ->
              body

            {:error, _} = val ->
              Logger.error(
                "an error happened while parsing 500, #{inspect(val)}, #{inspect(raw_body)}"
              )

              %{message: ""}
          end

        cond do
          String.contains?(body["message"] || "", "Video unavailable") ->
            Logger.warn("this is an unavailable youtube id")
            {:error, :video_unavailable}

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
    piped_call(:search, &Piped.trending/2, region, nil)
  end

  def deprecated_search_from_url(url, playlist_end \\ 20, retry_limit \\ false) do
    if String.contains?(url, "/results?") do
      case Ratelimit.for_text_search() do
        :ok ->
          do_search_from_url(url, playlist_end)

        :deny ->
          {:error, :overloaded_ytdlp_seats}
      end
    else
      do_search_from_url(url, playlist_end)
    end
  end

  defp do_search_from_url(url, playlist_end) do
    {status, result} =
      run_ytdlp(:search, [
        url,
        "--dump-json",
        "--flat-playlist",
        "--add-headers",
        "YouTube-Restrict:Moderate",
        "--playlist-end",
        to_string(playlist_end),
        "--extractor-args",
        "youtubetab:approximate_metadata"
      ])

    {stdout, stderr, exit_status} = from_result(result)

    case status do
      :ok ->
        {:ok,
         stdout
         |> String.split("\n", trim: true)
         |> Enum.map(&Jason.decode!/1)
         |> vrcjson_workaround}

      :error ->
        Logger.error("search exit with #{exit_status}. stdout: #{stdout}. stderr: #{stderr}.")
        handle_ytdlp_error(exit_status, stdout, stderr)
    end
  end

  @spec fetch_mp4_link(String.t()) :: {:ok, {String.t(), Integer.t() | nil}} | {:error, any()}
  def fetch_mp4_link(youtube_id) do
    # TODO piped subtitle metadata and mp4 links are the same code path. we can optimize this

    with {:ok, piped_response} <-
           piped_call(:mp4_link, &Piped.streams/2, youtube_id, nil) do
      wanted_video_result = extract_valid_streams(piped_response["videoStreams"])

      wanted_video_result =
        if piped_response["livestream"] do
          %{
            "url" => piped_response["hls"]
          }
        else
          wanted_video_result
        end

      unless wanted_video_result == nil do
        url = wanted_video_result["url"]
        uri = url |> URI.parse()
        expiry_timestamp = expiry_from_uri(uri)
        {:ok, {url |> unproxied_piped_url, expiry_timestamp, wanted_video_result}}
      else
        {:error, :no_valid_video_formats_found}
      end
    end
  end

  defp extract_valid_streams(incoming_video_streams) do
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

  defp unproxied_piped_url(url) when is_bitstring(url) do
    url
    |> URI.parse()
    |> unproxied_piped_url
  end

  defp unproxied_piped_url(%URI{} = uri) do
    query = (uri.query || "") |> URI.decode_query()
    host = query["host"] || uri.host

    uri
    |> Map.put(:host, host)
    |> Map.put(:authority, host)
    |> to_string
  end

  defp expiry_from_uri(uri) do
    expiry_from_query(uri) || expiry_from_path(uri)
  end

  def fetch_subtitles(youtube_id) do
    if String.starts_with?(youtube_id, "https://") do
      raise "invalid youtube id: #{youtube_id}"
    end

    {:ok, subtitles} = piped_call(:subtitles, &Piped.streams/2, youtube_id, "subtitles")

    subtitle_count =
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
        {subtitle, data} = Task.await(task)
        YtSearch.Subtitle.insert(youtube_id, subtitle["code"], data)
      end)
      |> Enum.count()

    unless subtitle_count == 0 do
      :ok
    else
      YtSearch.Subtitle.insert(youtube_id, "notfound", nil)
      nil
    end
  end

  defp handle_ytdlp_error(exit_status, stdout, stderr) do
    cond do
      String.contains?(stderr, "Video unavailable") ->
        Logger.warn("this is an unavailable youtube id")
        {:error, :video_unavailable}

      String.contains?(stderr, "This channel does not have a videos tab") ->
        {:error, :channel_without_videos_tab}

      String.contains?(stderr, "Premieres in") ->
        {:error, :upcoming_video}

      true ->
        {:error, {:invalid_exit_code, exit_status}}
    end
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

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

  def search_from_url(url, playlist_end \\ 20, retry_limit \\ false) do
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

  def do_search_from_url(url, playlist_end) do
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
    {status, result} =
      run_ytdlp(:mp4_link, [
        "--no-check-certificate",
        # TODO do we want cache-dir??
        "--no-cache-dir",
        "--rm-cache-dir",
        "-f",
        "mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]",
        "--dump-json",
        YtSearch.Youtube.Util.to_watch_url(youtube_id)
      ])

    {stdout, stderr, exit_status} = from_result(result)

    url_result =
      case status do
        :ok ->
          youtube_metadata =
            stdout
            |> Jason.decode!()

          {:ok, {youtube_metadata["url"], youtube_metadata}}

        :error ->
          Logger.error("fetch_mp4_link fail. #{exit_status} stdout: #{stdout} stderr: #{stderr}")
          handle_ytdlp_error(exit_status, stdout, stderr)
      end

    case url_result do
      {:ok, {url, meta}} ->
        uri = url |> URI.parse()

        expiry_timestamp = expiry_from_uri(uri)

        {:ok, {url, expiry_timestamp, meta}}

      any ->
        any
    end
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

  defp expiry_from_uri(uri) do
    expiry_from_query(uri) || expiry_from_path(uri)
  end

  def fetch_subtitles(youtube_url) do
    uri = youtube_url |> URI.parse()

    id =
      case uri.query do
        nil ->
          "any"

        value ->
          value
          |> URI.decode_query()
          |> Map.get("v")
      end

    subtitle_folder = "/tmp/yts-subtitles/#{id}"
    File.mkdir_p!(subtitle_folder)

    Logger.debug("outputting to #{subtitle_folder}")

    {status, result} =
      run_ytdlp(
        :subtitles,
        [
          "--skip-download",
          "--write-subs",
          "--write-auto-subs",
          "--sub-format",
          "vtt",
          "--sub-langs",
          "en-orig,en,en-US",
          youtube_url
        ],
        cd: subtitle_folder
      )

    {stdout, stderr, exit_status} = from_result(result)

    case status do
      :ok ->
        subtitles =
          Path.wildcard(subtitle_folder <> "/*#{id}*en*.vtt")
          |> Enum.map(fn child_path ->
            {child_path, File.read(child_path)}
          end)
          |> Enum.filter(fn {path, result} ->
            case result do
              {:ok, _data} ->
                true

              _ ->
                Logger.error("expected #{path} to work, got #{inspect(result)}")
                false
            end
          end)
          |> Enum.map(fn {path, {:ok, data}} ->
            subtitle =
              path
              |> Path.basename()
              |> String.split(".")
              |> Enum.at(-2)
              |> then(fn language ->
                YtSearch.Subtitle.insert(id, language, data)
              end)

            File.rm(path)
            subtitle
          end)

        if length(subtitles) == 0 do
          YtSearch.Subtitle.insert(id, "notfound", nil)
          nil
        else
          :ok
        end

      :error ->
        Logger.error("ytdlp gave #{exit_status}. stdout: #{stdout}. stderr: #{stderr}.")
        handle_ytdlp_error(exit_status, stdout, stderr)
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

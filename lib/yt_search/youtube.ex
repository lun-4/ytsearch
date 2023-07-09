defmodule YtSearch.Youtube do
  require Logger

  @spec ytdlp() :: String.t()
  defp ytdlp() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:ytdlp_path]
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
      IO.puts("inc #{type}")

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

  def search_from_url(url, playlist_end \\ 30) do
    CallCounter.inc(:search)

    case System.cmd(ytdlp(), [
           url,
           "--dump-json",
           "--flat-playlist",
           "--playlist-end",
           to_string(playlist_end),
           "--extractor-args",
           "youtubetab:approximate_metadata"
         ]) do
      {stdout, 0} ->
        # is good
        {:ok,
         stdout
         |> String.split("\n", trim: true)
         |> Enum.map(&Jason.decode!/1)
         |> vrcjson_workaround}

      {stdout, other_error_code} ->
        Logger.error("stdout: #{stdout}")
        {:error, {:invalid_error_code, other_error_code}}
    end
  end

  @spec fetch_mp4_link(String.t()) :: {:ok, {String.t(), Integer.t() | nil}} | {:error, any()}
  def fetch_mp4_link(youtube_id) do
    CallCounter.inc(:mp4_link)

    url_result =
      case System.cmd(ytdlp(), [
             "--no-check-certificate",
             # TODO do we want cache-dir??
             "--no-cache-dir",
             "--rm-cache-dir",
             "-f",
             "mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]",
             "--get-url",
             YtSearch.Youtube.Util.to_watch_url(youtube_id)
           ]) do
        {stdout, 0} ->
          trimmed = String.trim(stdout)

          if trimmed == "" do
            fetch_any_video_link(youtube_id)
          else
            {:ok, trimmed}
          end

        {stdout, other_error_code} ->
          Logger.error("fetch_mp4_link stdout: #{stdout} #{other_error_code}")
          Logger.error("fallbacking to any video link")
          fetch_any_video_link(youtube_id)
      end

    case url_result do
      {:ok, url} ->
        uri = url |> URI.parse()

        {expires, ""} =
          case uri.query do
            nil ->
              {nil, ""}

            value ->
              value
              |> URI.decode_query()
              |> Map.get("expire")
              |> Integer.parse()
          end

        {:ok, {url, expires}}

      any ->
        any
    end
  end

  defp fetch_any_video_link(youtube_id) do
    CallCounter.inc(:any_link)

    case System.cmd(ytdlp(), [
           "--no-check-certificate",
           # TODO do we want cache-dir??
           "--no-cache-dir",
           "--rm-cache-dir",
           "--get-url",
           YtSearch.Youtube.Util.to_watch_url(youtube_id)
         ]) do
      {stdout, 0} ->
        url =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.at(0)

        {:ok, url}

      {stdout, other_error_code} ->
        Logger.error("fetch_any_video_link stdout: #{stdout} #{other_error_code}")
        {:error, {:invalid_error_code, other_error_code}}
    end
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

    CallCounter.inc(:subtitles)

    case System.cmd(
           ytdlp(),
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
           cd: subtitle_folder,
           stderr_to_stdout: true
         ) do
      {stdout, 0} ->
        subtitles =
          Path.wildcard(subtitle_folder <> "/*#{id}*en*.vtt")
          |> Enum.map(fn child_path ->
            {child_path, File.read(child_path)}
          end)
          |> Enum.filter(fn {path, result} ->
            case result do
              {:ok, data} ->
                true

              _ ->
                Logger.error("expected #{path} to work, got #{inspect(result)}")
                false
            end
          end)
          |> Enum.map(fn {path, {:ok, data}} ->
            path
            |> Path.basename()
            |> String.split(".")
            |> Enum.at(-2)
            |> then(fn language ->
              YtSearch.Subtitle.insert(id, language, data)
            end)
          end)

        if length(subtitles) == 0 do
          YtSearch.Subtitle.insert(id, "notfound", nil)
          nil
        else
          :ok
        end

      {stdout, other_error_code} ->
        Logger.error("fetch_subtitles stdout: #{stdout} #{other_error_code}")
        {:error, {:invalid_exit_code, other_error_code}}
    end
  end
end

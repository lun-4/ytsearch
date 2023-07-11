defmodule YtSearch.Youtube do
  require Logger

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

  defp run_ytdlp(args, opts \\ []) do
    {status, result} =
      :exec.run(
        [ytdlp()] ++ args,
        [:sync, :stdout, :stderr] ++ opts
      )

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

  def search_from_url(url, playlist_end \\ 30) do
    CallCounter.inc(:search)

    {status, result} =
      run_ytdlp([
        url,
        "--dump-json",
        "--flat-playlist",
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
        Logger.error("stdout: #{stdout} #{stderr}")
        {:error, {:invalid_error_code, exit_status, stderr}}
    end
  end

  @spec fetch_mp4_link(String.t()) :: {:ok, {String.t(), Integer.t() | nil}} | {:error, any()}
  def fetch_mp4_link(youtube_id) do
    CallCounter.inc(:mp4_link)

    {status, result} =
      run_ytdlp([
        "--no-check-certificate",
        # TODO do we want cache-dir??
        "--no-cache-dir",
        "--rm-cache-dir",
        "-f",
        "mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]",
        "--get-url",
        YtSearch.Youtube.Util.to_watch_url(youtube_id)
      ])

    {stdout, stderr, exit_status} = from_result(result)

    url_result =
      case status do
        :ok ->
          trimmed = String.trim(stdout)

          if trimmed == "" do
            Logger.error("fetch_mp4_link fail. no url given, fallbacking...")
            fetch_any_video_link(youtube_id)
          else
            {:ok, trimmed}
          end

        :error ->
          Logger.error("fetch_mp4_link fail. #{exit_status} stdout: #{stdout} stderr: #{stderr}")
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

    {status, result} =
      run_ytdlp([
        "--no-check-certificate",
        # TODO do we want cache-dir??
        "--no-cache-dir",
        "--rm-cache-dir",
        "--get-url",
        YtSearch.Youtube.Util.to_watch_url(youtube_id)
      ])

    {stdout, stderr, exit_status} = from_result(result)

    case status do
      :ok ->
        url =
          stdout
          |> String.split("\n", trim: true)
          |> Enum.at(0)

        {:ok, url}

      :error ->
        Logger.error("fetch_any_video_link #{exit_status} stdout: #{stdout} stderr: #{stderr}")
        {:error, {:invalid_error_code, exit_status}}
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

    {status, result} =
      run_ytdlp(
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

      :error ->
        Logger.error("fetch_subtitles #{exit_status} stdout: #{stdout} stderr: #{stderr}")
        {:error, {:invalid_exit_code, exit_status}}
    end
  end
end

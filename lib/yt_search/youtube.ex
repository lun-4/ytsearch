defmodule YtSearch.Youtube do
  require Logger

  @spec ytdlp() :: String.t()
  defp ytdlp() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:ytdlp_path]
  end

  def search_from_url(url) do
    case System.cmd(ytdlp(), [
           url,
           "--dump-json",
           "--flat-playlist",
           "--playlist-end",
           "15",
           "--extractor-args",
           "youtubetab:approximate_metadata"
         ]) do
      {stdout, 0} ->
        # is good
        {:ok,
         stdout
         |> String.split("\n", trim: true)
         |> Enum.map(&Jason.decode!/1)}

      {stdout, other_error_code} ->
        Logger.error("stdout: #{stdout}")
        {:error, {:invalid_error_code, other_error_code}}
    end
  end

  @spec fetch_mp4_link(String.t()) :: {:ok, {String.t(), Integer.t() | nil}} | {:error, any()}
  def fetch_mp4_link(youtube_id) do
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

    subtitle_folder = "/tmp/yts-subtitles/" <> id
    File.mkdir_p!(subtitle_folder)

    Logger.debug("outputting to #{subtitle_folder}")

    case System.cmd(
           ytdlp(),
           [
             "--skip-download",
             "--write-subs",
             "--write-auto-subs",
             "--sub-format",
             "vtt",
             "--sub-langs",
             "en-orig,en",
             youtube_url
           ],
           cd: subtitle_folder,
           stderr_to_stdout: true
         ) do
      {stdout, 0} ->
        :ok

      {stdout, other_error_code} ->
        Logger.error("fetch_subtitles stdout: #{stdout} #{other_error_code}")
        {:error, {:invalid_exit_code, other_error_code}}
    end
  end
end

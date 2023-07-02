defmodule YtSearch.Youtube do
  require Logger

  @spec ytdlp() :: String.t()
  defp ytdlp() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:ytdlp_path]
  end

  def search(query) do
    escaped_query =
      query
      |> URI.encode()

    "https://www.youtube.com/results?search_query=#{escaped_query}"
    |> playlist_from_url
  end

  def channel_search(url) do
    url
    |> playlist_from_url
  end

  def playlist_from_url(url) do
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

  def fetch_mp4_link(youtube_id) do
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
    {:ok, temp_path} = Temp.mkdir("yts-subtitles")

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
           cd: temp_path,
           stderr_to_stdout: true
         ) do
      {stdout, 0} ->
        {filename, {:ok, subtitle_data}} =
          Regex.scan(~r/Destination: (.+)$/m, stdout)
          |> Enum.map(fn match ->
            filename = Enum.at(match, 1)
            {filename, File.read(temp_path <> "/" <> filename)}
          end)
          |> Enum.filter(fn {filename, result} ->
            case result do
              {:ok, data} ->
                true

              _ ->
                Logger.error("expected #{filename} to work, got #{inspect(result)}")
                false
            end
          end)
          |> Enum.at(0)

        {:ok, subtitle_data}

      {stdout, other_error_code} ->
        Logger.error("fetch_subtitles stdout: #{stdout} #{other_error_code}")
        {:error, {:invalid_exit_code, other_error_code}}
    end
  end
end

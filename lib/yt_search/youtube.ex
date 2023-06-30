defmodule YtSearch.Youtube do
  require Logger

  @spec ytdlp() :: String.t()
  defp ytdlp() do
    Application.fetch_env!(:yt_search, YtSearch.Youtube)[:ytdlp_path]
  end

  def search(query) do
    escaped_query = query |> URI.encode()

    case System.cmd(ytdlp, [
           "https://www.youtube.com/results?search_query=#{escaped_query}",
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
    {output, exit_status} =
      System.cmd(ytdlp, [
        "--no-check-certificate",
        # TODO do we want cache-dir??
        "--no-cache-dir",
        "--rm-cache-dir",
        "-f",
        "mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]",
        "--get-url",
        YtSearch.Youtube.Util.to_watch_url(youtube_id)
      ])

    String.trim(output)
  end
end

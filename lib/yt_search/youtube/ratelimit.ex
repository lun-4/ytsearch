defmodule YtSearch.Youtube.Ratelimit do
  def for_text_search(in_retry \\ false) do
    {requests, per_millisecond} =
      Application.fetch_env!(:yt_search, YtSearch.Ratelimit)[:ytdlp_search]

    # at the moment, only apply rate limiting to text searches
    # channels and playlists are exempt
    case Hammer.check_rate("ytdlp:search_call", per_millisecond, requests) do
      {:allow, _count} ->
        :ok

      {:deny, _limit} ->
        if in_retry do
          :deny
        else
          Process.sleep(1)
          # attempt again, if that fails again it'll 500
          for_text_search(true)
        end
    end
  end
end

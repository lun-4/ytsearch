defmodule YtSearch.Sponsorblock do
  # a SponsorBlock API micro-client

  use Tesla

  plug Tesla.Middleware.Headers, [{"accept", "application/json"}]
  plug Tesla.Middleware.JSON

  def skip_segments(api_url, youtube_id) do
    get(
      "#{api_url}/api/skipSegments?videoID=#{youtube_id}&categories=[\"sponsor\",\"poi_highlight\"]",
      opts: [adapter: [recv_timeout: 3000]]
    )
  end
end

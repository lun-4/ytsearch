defmodule YtSearch.Sponsorblock do
  # a SponsorBlock API micro-client

  use Tesla

  plug Tesla.Middleware.Headers, [{"accept", "application/json"}]
  plug Tesla.Middleware.JSON

  def skip_segments(api_url, youtube_id) do
    # final_url =
    #  "#{api_url}/api/skipSegments/#{first_hash}?categories=[\"sponsor\",\"intro\",\"outro\",\"selfpromo\",\"music_offtopic\",\"preview\"]"

    get("#{api_url}/api/skipSegments?videoID=#{youtube_id}")
  end
end

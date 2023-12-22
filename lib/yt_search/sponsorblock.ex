defmodule YtSearch.Sponsorblock do
  # a SponsorBlock API micro-client

  use Tesla

  plug Tesla.Middleware.Headers, [{"accept", "application/json"}]
  plug Tesla.Middleware.JSON

  def categories() do
    [
      "poi_highlight",
      "sponsor",
      "selfpromo",
      "interaction",
      "intro",
      "outro"
    ]
  end

  def encoded_categories,
    do:
      Jason.encode!(categories(),
        pretty: [indent: "", line_separator: "", after_colon: ""]
      )

  def skip_segments(api_url, youtube_id) do
    get(
      "#{api_url}/api/skipSegments?videoID=#{youtube_id}&categories=#{encoded_categories()}",
      opts: [adapter: [recv_timeout: 3000]]
    )
  end
end

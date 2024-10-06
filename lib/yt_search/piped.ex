defmodule YtSearch.Piped do
  # a Piped API micro-client

  use Tesla
  require Logger

  plug Tesla.Middleware.Headers, [{"accept", "application/json"}]
  plug Tesla.Middleware.JSON

  def search(url, text) do
    Logger.debug("piped: searching for #{text}")
    get("#{url}/search", query: [q: text, filter: "all"])
  end

  def nextpage_search(url, text, nextpage) do
    Logger.debug("piped: searching for #{text} at nextpage #{nextpage}")

    get("#{url}/nextpage/search",
      query: [q: text, filter: "all", nextpage: nextpage]
    )
  end

  def channel(url, id) do
    Logger.debug("piped: channel: #{id}")
    get("#{url}/channel/#{id}")
  end

  def nextpage_channel(url, id, nextpage) do
    Logger.debug("piped: nextpage channel: #{nextpage}")

    get("#{url}/nextpage/channel/#{id}",
      query: [nextpage: nextpage]
    )
  end

  def playlists(url, id) do
    Logger.debug("piped: playlists: #{id}")
    get("#{url}/playlists/#{id}")
  end

  def nextpage_playlists(url, id, nextpage) do
    Logger.debug("piped: nextpage playlists: #{nextpage}")

    get("#{url}/nextpage/playlists/#{id}",
      query: [nextpage: nextpage]
    )
  end

  def streams(url, id) do
    Logger.debug("piped: streams: #{id}")
    get("#{url}/streams/#{id}")
  end

  def trending(url, region) do
    Logger.debug("piped: trending")
    get("#{url}/trending", query: [region: region])
  end
end

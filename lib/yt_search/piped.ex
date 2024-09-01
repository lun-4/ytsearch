defmodule YtSearch.Piped do
  # a Piped API micro-client

  use Tesla

  plug Tesla.Middleware.Headers, [{"accept", "application/json"}]
  plug Tesla.Middleware.JSON

  def search(url, text) do
    get("#{url}/search", query: [q: text, filter: "all"])
  end

  def nextpage_search(url, text, nextpage) do
    get("#{url}/nextpage/search",
      query: [q: text, filter: "all", nextpage: nextpage]
    )
  end

  def channel(url, id) do
    get("#{url}/channel/#{id}")
  end

  def nextpage_channel(url, id, nextpage) do
    get("#{url}/nextpage/channel/#{id}",
      query: [nextpage: nextpage]
    )
  end

  def playlists(url, id) do
    get("#{url}/playlists/#{id}")
  end

  def nextpage_playlists(url, id, nextpage) do
    get("#{url}/nextpage/playlists/#{id}",
      query: [nextpage: nextpage]
    )
  end

  def streams(url, id) do
    get("#{url}/streams/#{id}")
  end

  def trending(url, region) do
    get("#{url}/trending", query: [region: region])
  end
end

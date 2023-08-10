defmodule YtSearch.Piped do
  # a Piped API micro-client

  use Tesla

  plug Tesla.Middleware.Headers, [{"accept", "application/json"}]
  plug Tesla.Middleware.JSON

  def search(url, text) do
    get("#{url}/search?q=#{text}&filter=all")
  end

  def channel(url, id) do
    get("#{url}/channel/#{id}")
  end

  def playlists(url, id) do
    get("#{url}/playlists/#{id}")
  end

  def streams(url, id) do
    get("#{url}/streams/#{id}")
  end

  def trending(url, region) do
    get("#{url}/trending?region=#{region}")
  end
end

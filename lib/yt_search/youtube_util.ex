defmodule YtSearch.Youtube.Util do
  def to_watch_url(youtube_id) do
    "https://youtube.com/watch?v=#{youtube_id}"
  end
end

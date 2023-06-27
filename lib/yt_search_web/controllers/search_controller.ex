defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  def search(conn, _params) do
    # TODO this can be nil
    search_query = conn.query_params["search"]
    IO.puts("want to do '#{search_query}'")

    escaped_query = search_query |> URI.encode()

    {output, exit_status} =
      System.cmd("yt-dlp", [
        "https://www.youtube.com/results?search_query=#{escaped_query}",
        "--dump-json",
        "--flat-playlist",
        "--playlist-end",
        "15"
      ])

    results =
      output
      |> IO.inspect()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.filter(fn data ->
        # dont give Channel entries (future stuff)
        data["ie_key"] == "Youtube"
      end)
      |> Enum.map(fn ytdlp_data ->
        slot = YtSearch.Slot.from(ytdlp_data["id"])

        %{
          title: ytdlp_data["title"],
          youtube_id: ytdlp_data["id"],
          youtube_url: ytdlp_data["url"],
          duration: ytdlp_data["duration"],
          channel_name: ytdlp_data["channel"],
          description: ytdlp_data["description"],
          uploaded_at: ytdlp_data["epoch"],
          view_count: ytdlp_data["view_count"],
          slot_id: "#{slot.id}"
        }
      end)

    conn
    |> json(%{search_results: results})
  end
end

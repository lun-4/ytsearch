defmodule YtSearchWeb.SearchController do
  use YtSearchWeb, :controller

  alias YtSearch.Youtube
  alias YtSearch.SearchSlot

  def search(conn, _params) do
    case conn.query_params["search"] || conn.query_params["q"] do
      nil ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "need search param fam"})

      search_query ->
        do_search(conn, search_query)
    end
  end

  def do_search(conn, search_query) do
    {:ok, youtube_json_results} = Youtube.search(search_query)

    results =
      youtube_json_results
      |> Enum.filter(fn data ->
        # dont give Channel entries (future stuff)
        data["ie_key"] == "Youtube"
      end)
      |> Enum.map(fn ytdlp_data ->
        # spawn background task for thumbnail fetching
        Youtube.Thumbnail.fetch_in_background(ytdlp_data)
        ytdlp_data
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
          uploaded_at: ytdlp_data["timestamp"],
          view_count: ytdlp_data["view_count"],
          slot_id: "#{slot.id}"
        }
      end)

    search_slot =
      results
      |> Enum.map(fn r ->
        {numeric, _fractional} = Integer.parse(r.slot_id)
        numeric
      end)
      |> Jason.encode!()
      |> SearchSlot.from()

    conn
    |> json(%{
      search_results: results,
      slot_id: "#{search_slot.id}"
    })
  end
end

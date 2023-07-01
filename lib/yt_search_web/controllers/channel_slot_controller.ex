defmodule YtSearchWeb.ChannelSlotController do
  use YtSearchWeb, :controller
  alias YtSearch.ChannelSlot
  alias YtSearch.SearchSlot
  alias YtSearch.Youtube
  alias YtSearchWeb.Playlist

  def fetch(conn, %{"channel_slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case ChannelSlot.fetch(slot_id) do
      nil ->
        conn
        |> put_status(404)

      slot ->
        {:ok, ytdlp_data} =
          "https://www.youtube.com/channel/#{slot.youtube_id}/videos"
          |> Youtube.channel_search()

        results =
          ytdlp_data
          |> Playlist.from_ytdlp_data()

        search_slot =
          results
          |> SearchSlot.from_playlist()

        conn
        |> json(%{search_results: results, slot_id: "#{search_slot.id}"})
    end
  end
end

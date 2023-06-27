defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  alias YtSearch.Slot

  def fetch_video(conn, %{"id" => slot_id}) do
    case Slot.fetch(slot_id) do
      nil ->
        conn
        |> put_status(404)

      slot ->
        # TODO verify user agent
        conn
        |> put_resp_header("location", slot.youtube_url)
        |> put_status(301)
    end
  end
end

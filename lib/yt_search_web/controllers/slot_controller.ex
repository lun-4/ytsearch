defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  alias YtSearch.Slot

  def fetch_video(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        conn
        |> put_status(404)

      slot ->
        # TODO verify user agent
        conn
        |> redirect(external: "https://youtube.com/watch?v=#{slot.youtube_id}")
    end
  end
end

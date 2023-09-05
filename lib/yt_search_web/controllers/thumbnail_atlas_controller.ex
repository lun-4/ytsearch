defmodule YtSearchWeb.AtlasController do
  use YtSearchWeb, :controller

  alias YtSearch.Thumbnail.Atlas

  def fetch(conn, %{"search_slot_id" => search_slot_id}) do
    case do_fetch(search_slot_id) do
      {:ok, mimetype, binary_data} ->
        conn
        |> put_resp_content_type(mimetype, nil)
        |> resp(200, binary_data)

      {:error, :unknown_search_slot} ->
        conn
        |> put_status(404)
        |> text("search slot not found")
    end
  end

  def do_fetch(search_slot_id) do
    Atlas.assemble(search_slot_id)
  end
end

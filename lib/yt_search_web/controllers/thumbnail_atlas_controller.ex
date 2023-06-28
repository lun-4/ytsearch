defmodule YtSearchWeb.AtlasController do
  use YtSearchWeb, :controller

  alias YtSearch.Thumbnail.Atlas

  def fetch(conn, %{"search_slot_id" => search_slot_id}) do
    {:ok, mimetype, binary_data} = do_fetch(search_slot_id)

    conn
    |> put_resp_content_type(mimetype, nil)
    |> resp(200, binary_data)
  end

  def do_fetch(search_slot_id) do
    Atlas.assemble(search_slot_id)
  end
end

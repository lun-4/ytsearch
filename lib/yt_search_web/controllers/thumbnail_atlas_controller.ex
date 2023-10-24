defmodule YtSearchWeb.AtlasController do
  use YtSearchWeb, :controller

  alias YtSearch.Slot
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

  def fetch_single_thumbnail(conn, %{"slot_id" => slot_id}) do
    slot_id
    |> Slot.fetch_by_id()
    |> then(fn
      nil ->
        # TODO empty thumb?
        conn
        |> put_status(404)
        |> text("search slot not found")

      slot ->
        {:ok, mimetype, binary_data} = Atlas.assemble_one(slot)

        conn
        |> put_resp_content_type(mimetype, nil)
        |> resp(200, binary_data)
    end)
  end

  def do_fetch(search_slot_id) do
    Atlas.assemble(search_slot_id)
  end
end

defmodule YtSearchWeb.SlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock
  alias YtSearch.Slot

  @youtube_id "Jouh2mdt1fI"

  test "it gets the mp4 url on quest useragents, supporting ttl", %{conn: conn} do
    with_mock(
      YtSearch.Youtube,
      fetch_mp4_link: [in_series([@youtube_id], [{:ok, "mp4.com"}, {:ok, "mp5.com"}])]
    ) do
      slot = Slot.from(@youtube_id)

      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == ["mp4.com"]

      link = YtSearch.Mp4Link.fetch_by_id(@youtube_id)
      assert link != nil

      link
      |> Ecto.Changeset.change(inserted_at: link.inserted_at |> NaiveDateTime.add(-5000, :second))
      |> YtSearch.Repo.update!()

      conn =
        build_conn()
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == ["mp5.com"]
    end
  end
end

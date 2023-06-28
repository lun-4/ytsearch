defmodule YtSearchWeb.SlotTest do
  use YtSearchWeb.ConnCase, async: true
  import Mock
  alias YtSearch.Slot

  @youtube_id "Jouh2mdt1fI"

  test "it gets the mp4 url on quest useragents", %{conn: conn} do
    with_mock(
      YtSearch.Youtube,
      fetch_mp4_link: fn _ ->
        "mp4.com"
      end
    ) do
      slot = Slot.from(@youtube_id)

      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == ["mp4.com"]
    end
  end
end

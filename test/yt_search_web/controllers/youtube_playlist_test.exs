defmodule YtSearchWeb.PlaylistSlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  @expected_playlist_id "PLnVSKQeK_aPbUZnaViFxSoLZy3-9WqgYz"
  @expected_youtube_id "8wo6sNbzlYk"

  @search_data File.read!("test/support/files/rez_infinite_search.json")
  @playlist_data File.read!("test/support/files/rez_infinite_playlist.json")
  setup do
    Hammer.delete_buckets("ytdlp:search_call")
    :ok
  end

  test "it gets the mp4 url on quest useragents, supporting ttl", %{conn: conn} do
    with_mock(
      :exec,
      run: [
        in_series([:_, :_], [{:ok, [stdout: [@search_data]]}, {:ok, [stdout: [@playlist_data]]}])
      ]
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/a/1/s?q=anything")

      rjson = json_response(conn, 200)
      first_result = rjson["search_results"] |> Enum.at(0)
      assert first_result["youtube_id"] == @expected_playlist_id
      assert first_result["type"] == "playlist"

      first_result_slot_id = first_result["slot_id"]

      conn =
        conn
        |> get(~p"/a/1/p/#{first_result_slot_id}")

      rjson = json_response(conn, 200)
      first_result = rjson["search_results"] |> Enum.at(0)
      assert first_result["youtube_id"] == @expected_youtube_id
      assert first_result["type"] == "video"
    end
  end
end

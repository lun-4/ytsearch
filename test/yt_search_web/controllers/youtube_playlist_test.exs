defmodule YtSearchWeb.PlaylistSlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Tesla.Mock

  setup do
    YtSearch.Test.Data.default_global_mock()
  end

  @expected_playlist_id "PLnVSKQeK_aPbUZnaViFxSoLZy3-9WqgYz"
  @expected_youtube_id "8wo6sNbzlYk"

  @search_data File.read!("test/support/piped_outputs/rez_infinite_search.json")
  @playlist_data File.read!("test/support/piped_outputs/rez_infinite_playlist.json")

  test "it handles playlist requests successfully", %{conn: conn} do
    mock(fn
      %{method: :get, url: "example.org/playlists" <> _} ->
        json(Jason.decode!(@playlist_data))

      %{method: :get, url: "example.org/search" <> _} ->
        json(Jason.decode!(@search_data))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/1/s?q=anything")

    rjson = json_response(conn, 200)
    first_result = rjson["search_results"] |> Enum.at(0)
    assert first_result["youtube_id"] == @expected_playlist_id
    assert first_result["type"] == "playlist"
    assert first_result["title"] != nil

    first_result_slot_id = first_result["slot_id"]

    conn =
      conn
      |> get(~p"/a/1/p/#{first_result_slot_id}")

    rjson = json_response(conn, 200)
    first_result = rjson["search_results"] |> Enum.at(0)
    assert first_result["youtube_id"] == @expected_youtube_id
    assert first_result["type"] == "video"
  end

  test "it 404s on unknown playlist ids", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/1/p/18247")

    assert conn.status == 404
  end
end

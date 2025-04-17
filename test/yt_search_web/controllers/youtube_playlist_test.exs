defmodule YtSearchWeb.PlaylistSlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Tesla.Mock

  setup do
    ets = :ets.new(:mock_call_counter, [:public])
    YtSearch.Test.Data.default_global_mock()
    %{ets_table: ets}
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
      |> get(~p"/a/6/s?q=anything")

    rjson = json_response(conn, 200)
    first_result = rjson["search_results"] |> Enum.at(0)
    assert first_result["youtube_id"] == @expected_playlist_id
    assert first_result["type"] == "playlist"
    assert first_result["title"] != nil

    first_result_slot_id = first_result["slot_id"]

    conn =
      conn
      |> get(~p"/a/6/p/#{first_result_slot_id}")

    rjson = json_response(conn, 200)
    first_result = rjson["search_results"] |> Enum.at(0)
    assert first_result["youtube_id"] == @expected_youtube_id
    assert first_result["type"] == "video"
  end

  test "it 404s on unknown playlist ids", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/6/p/18247")

    assert conn.status == 404
  end

  defp assert_playlist_result(rjson) do
    assert rjson["type"] == nil || rjson["type"] == "playlist"
    assert rjson["title"] == nil || rjson["title"] == "Rez Infinite Original Soundtrack"
    first_result = rjson["search_results"] |> Enum.at(0)
    assert first_result["youtube_id"] == @expected_youtube_id
  end

  test "nextpage works on playlists", %{conn: conn, ets_table: table} do
    mock(fn
      %{method: :get, url: "example.org/playlists" <> _} ->
        json(Jason.decode!(@playlist_data))

      %{method: :get, url: "example.org/nextpage/playlists" <> _whatever} ->
        calls = :ets.update_counter(table, :playlist_nextpage, 1, {:playlist_nextpage, 0})

        json(
          case calls do
            1 ->
              Jason.decode!(@playlist_data)
              |> Map.put("nextpage", "test13951830498")

            2 ->
              %{
                relatedStreams: [],
                nextpage: nil
              }
          end
        )

      %{method: :get, url: "example.org/search" <> _} ->
        json(Jason.decode!(@search_data))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/s?q=anything")

    rjson = json_response(conn, 200)
    first_result = rjson["search_results"] |> Enum.at(0)
    assert first_result["youtube_id"] == @expected_playlist_id

    playlist_slot_id = first_result["slot_id"]

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/p/#{playlist_slot_id}")

    rjson = json_response(conn, 200)
    assert :ets.lookup(table, :playlist_nextpage) == []
    assert_playlist_result(rjson)

    nextpage_slot_id = rjson["nextpage_slot_id"]
    assert nextpage_slot_id != nil

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot_id}")

    rjson = json_response(conn, 200)

    conn2 =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot_id}")

    rjson2 = json_response(conn2, 200)
    assert rjson |> Map.delete("__x_request_id") == rjson2 |> Map.delete("__x_request_id")

    assert :ets.lookup(table, :playlist_nextpage) == [playlist_nextpage: 1]
    assert_playlist_result(rjson)

    nextpage_slot_id = rjson["nextpage_slot_id"]
    assert nextpage_slot_id != nil

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/6/r/#{nextpage_slot_id}")

    rjson = json_response(conn, 200)
    assert :ets.lookup(table, :playlist_nextpage) == [playlist_nextpage: 2]
    nextpage_slot_id = rjson["nextpage_slot_id"]
    assert nextpage_slot_id == nil
  end
end

defmodule YtSearchWeb.GiftDropTest do
  use YtSearchWeb.ConnCase, async: false

  setup %{conn: conn} do
    YtSearch.Test.Data.default_global_mock()
    conn = put_req_header(conn, "user-agent", "UnityWebRequest")
    {:ok, conn: conn}
  end

  describe "GET /a/6/g/:number" do
    test "increments gift counter and persists to db", %{conn: conn} do
      conn1 = get(conn, ~p"/a/6/g/5")
      rjson1 = json_response(conn1, 200)
      assert rjson1["added"] == 5
      gifts1 = rjson1["gifts"]

      conn2 = get(conn, ~p"/a/6/g/3")
      rjson2 = json_response(conn2, 200)
      assert rjson2["added"] == 3
      gifts2 = rjson2["gifts"]

      assert gifts2 - gifts1 == 3

      assert YtSearch.Counter.get_value(:gift_drops) == gifts2
    end

    test "does not affect the global counter", %{conn: conn} do
      global_before = YtSearch.Counter.get_value()

      get(conn, ~p"/a/6/g/10")

      global_after = YtSearch.Counter.get_value()

      assert global_after == global_before
    end

    test "rejects zero amount", %{conn: conn} do
      conn2 = get(conn, ~p"/a/6/g/0")
      _ = json_response(conn2, 400)
    end

    test "rejects amount over 100", %{conn: conn} do
      conn2 = get(conn, ~p"/a/6/g/101")
      _ = json_response(conn2, 400)
    end

    test "rejects non-integer amount", %{conn: conn} do
      conn2 = get(conn, ~p"/a/6/g/abc")
      _ = json_response(conn2, 400)
    end

    test "rejects requests without unity user agent", %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0")

      conn2 = get(conn, ~p"/a/6/g/5")
      _ = json_response(conn2, 400)
    end
  end
end

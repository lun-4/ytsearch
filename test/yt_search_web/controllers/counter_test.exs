defmodule YtSearchWeb.CounterTest do
  use YtSearchWeb.ConnCase, async: false

  import Tesla.Mock

  alias YtSearch.Counter
  alias YtSearch.CounterServer
  alias YtSearch.Data.CounterRepo

  setup do
    YtSearch.Test.Data.default_global_mock()
    :ok
  end

  describe "GET /a/6/co/:delta" do
    test "increments counter by positive delta", %{conn: conn} do
      conn1 = get(conn, ~p"/a/6/co/0")
      initial = json_response(conn1, 200)["counter"]

      conn2 = get(conn, ~p"/a/6/co/5")
      rjson = json_response(conn2, 200)
      final = rjson["counter"]
      assert rjson["added"] == 5

      assert final - initial == 5.0
    end

    test "handles zero delta", %{conn: conn} do
      conn1 = get(conn, ~p"/a/6/co/0")
      initial = json_response(conn1, 200)["counter"]

      conn2 = get(conn, ~p"/a/6/co/0")
      final = json_response(conn2, 200)["counter"]

      assert final - initial == 0.0
    end

    test "rejects negative delta", %{conn: conn} do
      conn1 = get(conn, ~p"/a/6/co/0")
      initial = json_response(conn1, 200)["counter"]

      # Try negative delta
      conn2 = get(conn1, ~p"/a/6/co/-20")
      _ = json_response(conn2, 400)

      conn3 = get(conn2, ~p"/a/6/co/0")
      final = json_response(conn3, 200)["counter"]

      # no change to delta
      assert final - initial == 0.0
    end

    test "rejects 1000+ delta", %{conn: conn} do
      conn1 = get(conn, ~p"/a/6/co/0")
      initial = json_response(conn1, 200)["counter"]

      conn2 = get(conn1, ~p"/a/6/co/1500")
      _ = json_response(conn2, 400)

      conn3 = get(conn2, ~p"/a/6/co/0")
      final = json_response(conn3, 200)["counter"]

      # no change to delta
      assert final - initial == 0.0
    end

    test "accumulates multiple increments", %{conn: conn} do
      # Get initial value
      conn1 = get(conn, ~p"/a/6/co/0")
      initial = json_response(conn1, 200)["counter"]

      # Multiple increments
      get(conn, ~p"/a/6/co/10")
      get(conn, ~p"/a/6/co/20")
      conn_final = get(conn1, ~p"/a/6/co/30")
      final = json_response(conn_final, 200)["counter"]

      # 0 + 10 + 20 + 30
      assert final - initial == 60.0
    end

    test "handles invalid delta gracefully", %{conn: conn} do
      conn1 = get(conn, ~p"/a/6/co/0")
      initial = json_response(conn1, 200)["counter"]

      conn2 = get(conn1, ~p"/a/6/co/invalid")
      _ = json_response(conn2, 400)

      conn3 = get(conn2, ~p"/a/6/co/0")
      final = json_response(conn3, 200)["counter"]

      assert final - initial == 0.0
    end
  end

  describe "hello endpoint integration" do
    test "hello endpoint includes counter value", %{conn: conn} do
      conn1 = get(conn, ~p"/api/v6/hello")
      initial_hello = json_response(conn1, 200)["counter_data"]["counter"]

      # Increment counter
      conn2 = get(conn1, ~p"/a/6/co/25")

      # Check hello endpoint shows the increment
      conn3 = get(conn2, ~p"/api/v6/hello")
      final_hello = json_response(conn3, 200)["counter_data"]["counter"]

      assert json_response(conn3, 200)["online"] == true
      assert final_hello - initial_hello == 25.0
    end
  end
end

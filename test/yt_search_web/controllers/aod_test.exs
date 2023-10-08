defmodule YtSearchWeb.AngelOfDeathTest do
  use YtSearchWeb.ConnCase, async: true

  test "aod works", %{conn: conn} do
    conn =
      conn
      |> get(~p"/a/4/aod/1")

    resp_json = json_response(conn, 200)
    assert resp_json == nil
  end
end

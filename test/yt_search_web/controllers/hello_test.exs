defmodule YtSearchWeb.HelloTest do
  use YtSearchWeb.ConnCase, async: false

  test "/hello route works", %{conn: conn} do
    conn =
      conn
      |> get(~p"/api/v1/hello")

    resp_json = json_response(conn, 200)
    assert resp_json["online"] == true
  end
end

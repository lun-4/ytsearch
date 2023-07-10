defmodule YtSearchWeb.HelloTest do
  use YtSearchWeb.ConnCase, async: false

  import Mock

  @test_cases [
    "trending_tab.json",
    "trending_tab_2.json"
  ]

  @test_cases
  |> Enum.map(fn path -> "test/support/files/#{path}" end)
  |> Enum.map(fn path -> {path, File.read!(path)} end)
  |> Enum.each(fn {path, file_data} ->
    test "it works on " <> path, %{conn: conn} do
      with_mock(
        System,
        [:passthrough],
        cmd: fn _, _args ->
          {unquote(file_data), 0}
        end
      ) do
        conn =
          conn
          |> get(~p"/api/v1/hello")

        resp_json = json_response(conn, 200)
        assert resp_json["online"] == true
        assert is_bitstring(resp_json["__x_request_id"])
      end
    end
  end)
end

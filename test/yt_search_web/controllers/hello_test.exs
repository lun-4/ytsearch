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
        cmd: fn _, args ->
          {unquote(file_data), 0}
        end
      ) do
        conn =
          conn
          |> get(~p"/api/v1/hello")

        resp_json = json_response(conn, 200)
        assert resp_json["online"] == true
      end
    end
  end)
end

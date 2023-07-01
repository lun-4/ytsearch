defmodule YtSearchWeb.SearchBatchTest do
  use YtSearchWeb.ConnCase, async: false

  import Mock

  @test_cases [
    "agirisan_search.json",
    "bigclivedotcom_search.json",
    "bigclivedotcom_channel.json"
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
          |> get(~p"/api/v1/search?search=whatever")

        resp_json = json_response(conn, 200)
      end
    end
  end)
end

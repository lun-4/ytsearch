defmodule YtSearchWeb.HelloTest do
  use YtSearchWeb.ConnCase, async: false

  import Tesla.Mock

  @test_cases [
    "trending_tab.json"
  ]

  setup do
    YtSearch.Test.Data.default_global_mock()
  end

  @test_cases
  |> Enum.map(fn path -> "test/support/piped_outputs/#{path}" end)
  |> Enum.map(fn path -> {path, File.read!(path)} end)
  |> Enum.each(fn {path, file_data} ->
    test "it works on " <> path, %{conn: conn} do
      mock(fn
        %{method: :get, url: "example.org/trending" <> _suffix} ->
          json(Jason.decode!(unquote(file_data)))
      end)

      conn =
        conn
        |> get(~p"/api/v4/hello")

      resp_json = json_response(conn, 200)
      assert resp_json["online"] == true
      assert is_bitstring(resp_json["__x_request_id"])
    end
  end)
end

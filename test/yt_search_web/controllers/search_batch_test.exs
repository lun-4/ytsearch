defmodule YtSearchWeb.SearchBatchTest do
  use YtSearchWeb.ConnCase, async: false

  import Tesla.Mock

  setup_all do
    YtSearch.Test.Data.default_global_mock()
  end

  @test_cases [
    "agirisan_search.json",
    "bigclivedotcom_search.json",
    "lofi_search.json",
    "rez_infinite_search.json"
  ]

  @test_cases
  |> Enum.map(fn path -> "test/support/piped_outputs/#{path}" end)
  |> Enum.map(fn path -> {path, File.read!(path)} end)
  |> Enum.each(fn {path, file_data} ->
    test "it works on " <> path, %{conn: conn} do
      mock(fn
        %{method: :get, url: "example.org" <> _suffix} ->
          json(Jason.decode!(unquote(file_data)))
      end)

      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v5/search?search=whatever")

      json_response(conn, 200)
    end
  end)
end

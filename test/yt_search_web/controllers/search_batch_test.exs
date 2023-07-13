defmodule YtSearchWeb.SearchBatchTest do
  use YtSearchWeb.ConnCase, async: false

  import Mock

  @test_cases [
    "agirisan_search.json",
    "bigclivedotcom_search.json",
    "bigclivedotcom_channel.json",
    "lofi_search.json",
    "rez_infinite_search.json"
  ]

  setup do
    Hammer.delete_buckets("ytdlp:search_call")
    :ok
  end

  @test_cases
  |> Enum.map(fn path -> "test/support/files/#{path}" end)
  |> Enum.map(fn path -> {path, File.read!(path)} end)
  |> Enum.each(fn {path, file_data} ->
    test "it works on " <> path, %{conn: conn} do
      with_mock(
        :exec,
        run: fn _, _ ->
          {:ok, [stdout: [unquote(file_data)]]}
        end
      ) do
        conn =
          conn
          |> put_req_header("user-agent", "UnityWebRequest")
          |> get(~p"/api/v1/search?search=whatever")

        json_response(conn, 200)
      end
    end
  end)
end

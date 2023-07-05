defmodule YtSearchWeb.TrendingTabTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  @test_output File.read!("test/support/files/trending_tab.json")

  test "trending tab works", %{conn: conn} do
    with_mock(
      System,
      [:passthrough],
      cmd: fn _, args ->
        {@test_output, 0}
      end
    ) do
      conn =
        conn
        |> get(~p"/api/v1/trending")

      resp_json = json_response(conn, 200)
      results = resp_json["search_results"]
      assert results |> Enum.at(0) |> Map.get("youtube_id") == "0GhMlekKPgo"
      assert results |> Enum.at(3) |> Map.get("youtube_id") == "qOXv-cPYd4g"
    end
  end
end
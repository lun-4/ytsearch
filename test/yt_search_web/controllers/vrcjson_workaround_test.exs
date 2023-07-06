defmodule YtSearchWeb.VRCJSONWorkaroundTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock

  @test_output File.read!(
                 "test/support/files/peaceful_summer_night_chill_summer_lofi_search.json"
               )

  test "it does the thing", %{conn: conn} do
    with_mock(
      System,
      [:passthrough],
      cmd: fn _, args ->
        {@test_output, 0}
      end
    ) do
      conn =
        conn
        |> get(~p"/api/v1/search?search=anything")

      resp_json = json_response(conn, 200)
      fourth_result = resp_json["search_results"] |> Enum.at(3)
      assert fourth_result["youtube_id"] == "sMnvdS4w9rU"

      assert fourth_result["title"] ==
               "\"Peaceful Summer Night \\ud83c\\udf15 90'S Chill Lofi \\ud83c\\udf15 Deep Focus To Study/Work  Lofi Hip Hop - Lofi Chill\""
               |> Jason.decode!()
    end
  end
end

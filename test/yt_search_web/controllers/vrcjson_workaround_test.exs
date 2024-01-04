defmodule YtSearchWeb.VRCJSONWorkaroundTest do
  use YtSearchWeb.ConnCase, async: true
  import Tesla.Mock
  alias YtSearch.Test.Data

  @test_output File.read!(
                 "test/support/piped_outputs/peaceful_summer_night_chill_summer_lofi_search.json"
               )

  test "it does the thing", %{conn: conn} do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org" <> _} ->
        json(Jason.decode!(@test_output))
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/api/v5/search?search=anything")

    resp_json = json_response(conn, 200)
    fourth_result = resp_json["search_results"] |> Enum.at(0)
    assert fourth_result["youtube_id"] == "rSXWZzh-GaU"

    assert fourth_result["title"] ==
             "\"Peaceful Summer Night \\uD83C\\uDF1D Chill Summer Lofi \\uD83C\\uDF1D Deep Focus To Study/Work  Lofi Hip Hop - Lofi Chill\""
             |> Jason.decode!()
  end
end

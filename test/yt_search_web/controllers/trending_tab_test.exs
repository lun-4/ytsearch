defmodule YtSearchWeb.TrendingTabTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock
  alias YtSearch.Slot

  @test_output File.read!("test/support/files/trending_tab.json")

  test "trending tab works", %{conn: conn} do
    with_mock(
      :exec,
      run: fn _, _ ->
        {:ok, [stdout: [@test_output]]}
      end
    ) do
      conn =
        conn
        |> get(~p"/api/v1/hello")

      resp_json = json_response(conn, 200)
      results = resp_json["trending_tab"]["search_results"]
      assert results |> Enum.at(0) |> Map.get("youtube_id") == "0GhMlekKPgo"
      assert results |> Enum.at(3) |> Map.get("youtube_id") == "qOXv-cPYd4g"

      {slot_id, ""} = results |> Enum.at(0) |> Map.get("slot_id") |> Integer.parse()

      slot = Slot.fetch_by_id(slot_id)

      slot_before =
        slot
        |> Ecto.Changeset.change(
          inserted_at: slot.inserted_at |> NaiveDateTime.add(-(Slot.max_ttl() + 1), :second),
          inserted_at_v2: slot.inserted_at_v2 - Slot.max_ttl() + 1
        )
        |> YtSearch.Repo.update!()

      YtSearchWeb.HelloController.Refresher.do_refresh()
      slot_after = Slot.fetch_by_id(slot_id)
      assert slot_after.inserted_at_v2 > slot_before.inserted_at_v2
      assert slot_after.inserted_at > slot_before.inserted_at

      # re-request it
      conn =
        conn
        |> get(~p"/api/v1/hello")

      resp_json = json_response(conn, 200)
      results2 = resp_json["trending_tab"]["search_results"]
      assert results2 |> Enum.at(0) == results |> Enum.at(0)
      assert results2 |> Enum.at(3) == results |> Enum.at(3)
    end
  end
end

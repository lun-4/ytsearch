defmodule YtSearchWeb.TrendingTabTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock
  alias YtSearch.Slot
  alias YtSearch.SearchSlot

  @test_output File.read!("test/support/piped_outputs/trending_tab.json")

  test "trending tab works", %{conn: conn} do
    Tesla.Mock.mock(fn
      %{method: :get, url: "example.org/trending?region=US"} ->
        Tesla.Mock.json(
          @test_output
          |> Jason.decode!()
        )
    end)

    conn =
      conn
      |> get(~p"/api/v1/hello")

    resp_json = json_response(conn, 200)
    results = resp_json["trending_tab"]["search_results"]
    assert results |> Enum.at(0) |> Map.get("youtube_id") == "HYzyRHAHJl8"
    assert results |> Enum.at(3) |> Map.get("youtube_id") == "AsvGScyj4gw"

    {slot_id, ""} = results |> Enum.at(0) |> Map.get("slot_id") |> Integer.parse()

    slot = Slot.fetch_by_id(slot_id)

    slot_before =
      slot
      |> Ecto.Changeset.change(
        inserted_at: slot.inserted_at |> NaiveDateTime.add(-(Slot.max_ttl() + 1), :second),
        inserted_at_v2: slot.inserted_at_v2 - Slot.max_ttl() + 1
      )
      |> YtSearch.Repo.update!()

    search_slot_id = resp_json["trending_tab"]["slot_id"]

    search_slot_before =
      SearchSlot.fetch_by_id(search_slot_id)
      |> Ecto.Changeset.change(
        inserted_at: slot.inserted_at |> NaiveDateTime.add(-(SearchSlot.ttl() + 1), :second)
      )
      |> YtSearch.Repo.update!()

    YtSearchWeb.HelloController.Refresher.tick()

    search_slot_after = SearchSlot.fetch_by_id(search_slot_id)
    assert search_slot_after != nil

    slot_after = Slot.fetch_by_id(slot_id)
    assert slot_after.inserted_at_v2 > slot_before.inserted_at_v2
    assert slot_after.inserted_at > slot_before.inserted_at
    assert search_slot_after.inserted_at > search_slot_before.inserted_at

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

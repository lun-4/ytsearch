defmodule YtSearchWeb.TrendingTabTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot

  @test_output File.read!("test/support/piped_outputs/trending_tab.json")

  setup do
    YtSearch.Test.Data.default_global_mock()

    # prevent a /hello done by another test from interfering with this one
    # (especially important as cachex does not have a sandbox mode akin to ecto sql)
    Cachex.del(:tabs, "trending")
    :ok
  end

  1..3
  |> Enum.each(fn num ->
    test "trending tab works #{num}", %{conn: conn} do
      Tesla.Mock.mock(fn
        %{method: :get, url: "example.org/trending", query: [region: "US"]} ->
          Tesla.Mock.json(
            @test_output
            |> Jason.decode!()
          )
      end)

      conn =
        conn
        |> get(~p"/api/v3/hello")

      resp_json = json_response(conn, 200)
      results = resp_json["trending_tab"]["search_results"]
      assert length(results) == 20
      assert results |> Enum.at(0) |> Map.get("youtube_id") == "HYzyRHAHJl8"
      assert results |> Enum.at(3) |> Map.get("youtube_id") == "AsvGScyj4gw"

      {slot_id, ""} = results |> Enum.at(0) |> Map.get("slot_id") |> Integer.parse()
      {channel_slot_id, ""} = results |> Enum.at(0) |> Map.get("channel_slot") |> Integer.parse()

      slot = Slot.fetch_by_id(slot_id)
      assert slot.keepalive

      slot_before =
        slot
        |> Ecto.Changeset.change(
          expires_at:
            NaiveDateTime.utc_now() |> NaiveDateTime.add(-30) |> NaiveDateTime.truncate(:second)
        )
        |> YtSearch.Repo.update!()

      channel_slot_before =
        ChannelSlot.fetch(channel_slot_id)
        |> Ecto.Changeset.change(
          expires_at:
            NaiveDateTime.utc_now() |> NaiveDateTime.add(-30) |> NaiveDateTime.truncate(:second)
        )
        |> YtSearch.Repo.update!()

      search_slot_id = resp_json["trending_tab"]["slot_id"]

      search_slot_before =
        SearchSlot.fetch_by_id(search_slot_id)

      # |> Ecto.Changeset.change(
      #  inserted_at: slot.inserted_at |> NaiveDateTime.add(-(SearchSlot.ttl() + 1), :second)
      # )
      # |> YtSearch.Repo.update!()

      search_slot_after = SearchSlot.fetch_by_id(search_slot_id)
      assert search_slot_after != nil

      slot_after = Slot.fetch_by_id(slot_id)
      assert slot_after.keepalive

      channel_slot_after = ChannelSlot.fetch(channel_slot_id)
      assert channel_slot_after.keepalive

      # re-request it
      conn =
        conn
        |> get(~p"/api/v3/hello")

      resp_json = json_response(conn, 200)
      results2 = resp_json["trending_tab"]["search_results"]
      assert results2 |> Enum.at(0) == results |> Enum.at(0)
      assert results2 |> Enum.at(3) == results |> Enum.at(3)
    end
  end)
end

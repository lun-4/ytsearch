defmodule YtSearchWeb.TrendingTabTest do
  alias YtSearch.Data.ChannelSlotRepo
  alias YtSearch.Data.SlotRepo
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.SearchSlot
  alias YtSearch.ChannelSlot

  @test_output File.read!("test/support/piped_outputs/trending_tab.json")
  @test_output_2 File.read!("test/support/piped_outputs/trending_tab_2.json")

  setup do
    YtSearch.Test.Data.default_global_mock()

    # prevent a /hello done by another test from interfering with this one
    # (especially important as cachex does not have a sandbox mode akin to ecto sql)
    Cachex.del(:tabs, "trending")

    ets = :ets.new(:mock_call_counter_trending_test, [:public])
    %{ets_table: ets}
  end

  1..3
  |> Enum.each(fn num ->
    test "trending tab works #{num}", %{conn: conn, ets_table: table} do
      Tesla.Mock.mock(fn
        %{method: :get, url: "example.org/trending", query: [region: "US"]} ->
          calls =
            :ets.update_counter(
              table,
              :trending_tab_test_counter,
              1,
              {:trending_tab_test_counter, 0}
            )

          Tesla.Mock.json(
            case calls do
              1 ->
                Jason.decode!(@test_output)

              2 ->
                Jason.decode!(@test_output_2)
            end
          )
      end)

      expected_length =
        Application.get_env(:yt_search, YtSearch.Constants)[:results_from_trending]

      conn =
        conn
        |> get(~p"/api/v5/hello")

      resp_json = json_response(conn, 200)
      results = resp_json["trending_tab"]["search_results"]
      assert length(results) == expected_length
      assert results |> Enum.at(0) |> Map.get("youtube_id") == "HYzyRHAHJl8"
      assert results |> Enum.at(3) |> Map.get("youtube_id") == "AsvGScyj4gw"

      {slot_id, ""} = results |> Enum.at(0) |> Map.get("slot_id") |> Integer.parse()
      {channel_slot_id, ""} = results |> Enum.at(0) |> Map.get("channel_slot") |> Integer.parse()

      slot = Slot.fetch_by_id(slot_id)
      assert slot.keepalive

      slot
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now() |> NaiveDateTime.add(-30) |> NaiveDateTime.truncate(:second)
      )
      |> SlotRepo.update!()

      ChannelSlot.fetch(channel_slot_id)
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now() |> NaiveDateTime.add(-30) |> NaiveDateTime.truncate(:second)
      )
      |> ChannelSlotRepo.update!()

      search_slot_id = resp_json["trending_tab"]["slot_id"]

      _ = SearchSlot.fetch(search_slot_id)

      slot
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-10, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> SlotRepo.update!()

      search_slot_after = SearchSlot.fetch(search_slot_id)
      assert search_slot_after != nil

      slot_after = Slot.fetch_by_id(slot_id)
      assert slot_after.keepalive

      channel_slot_after = ChannelSlot.fetch(channel_slot_id)
      assert channel_slot_after.keepalive

      # re-request it
      conn =
        conn
        |> get(~p"/api/v5/hello")

      resp_json = json_response(conn, 200)
      results2 = resp_json["trending_tab"]["search_results"]
      assert results2 |> Enum.at(0) == results |> Enum.at(0)
      assert results2 |> Enum.at(3) == results |> Enum.at(3)

      search_slot_after_rereq = SearchSlot.fetch(resp_json["trending_tab"]["slot_id"])
      assert search_slot_after_rereq != nil

      # every slot should be keepalive
      search_slot_after_rereq
      |> SearchSlot.fetched_slots_from_search(
        follow_inner_channel: true,
        follow_nextpage: true
      )
      |> Enum.each(fn slot ->
        assert slot.keepalive
      end)
    end
  end)

  def expire_search_slot(search_slot),
    do:
      search_slot
      |> Ecto.Changeset.change(
        expires_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-10, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> YtSearch.Data.SearchSlotRepo.update!()

  test "trending tab successfully switches slots' keepalive state when cache expires",
       %{
         conn: conn,
         ets_table: table
       } do
    Tesla.Mock.mock(fn
      %{method: :get, url: "example.org/trending", query: [region: "US"]} ->
        calls =
          :ets.update_counter(
            table,
            :trending_tab_test_counter,
            1,
            {:trending_tab_test_counter, 0}
          )

        Tesla.Mock.json(
          case calls do
            1 ->
              Jason.decode!(@test_output)

            2 ->
              Jason.decode!(@test_output_2)
          end
        )
    end)

    conn =
      conn
      |> get(~p"/api/v5/hello")

    resp_json = json_response(conn, 200)
    results = resp_json["trending_tab"]["search_results"]
    search_slot_id = resp_json["trending_tab"]["slot_id"]

    search_slot_before = SearchSlot.fetch(search_slot_id)
    assert search_slot_before != nil

    # every slot should be keepalive
    search_slot_before
    |> SearchSlot.fetched_slots_from_search(
      follow_inner_channel: true,
      follow_nextpage: true
    )
    |> Enum.each(fn slot ->
      assert slot.keepalive
    end)

    search_slot_before
    |> SearchSlot.fetched_slots_from_search()
    |> then(fn fetched_slots ->
      assert length(fetched_slots) == length(results)
    end)

    {:ok, true} = Cachex.del(:tabs, "trending")

    # search_slot_after = SearchSlot.fetch(search_slot_id)
    # assert search_slot_after == nil

    # re-request it
    conn =
      conn
      |> get(~p"/api/v5/hello")

    [trending_tab_test_counter: call_counter] =
      :ets.lookup(
        table,
        :trending_tab_test_counter
      )

    assert call_counter == 2

    resp_json = json_response(conn, 200)
    search_slot_id_after = resp_json["trending_tab"]["slot_id"]
    assert search_slot_id == search_slot_id_after

    search_slot_after = SearchSlot.fetch(search_slot_id_after)
    assert search_slot_after != nil

    # every slot should be keepalive
    search_slot_after
    |> SearchSlot.fetched_slots_from_search(
      follow_inner_channel: true,
      follow_nextpage: true
    )
    |> Enum.each(fn slot ->
      if not slot.keepalive do
        raise ArgumentError, "slot #{inspect(slot)} is not keepalive"
      end
    end)
  end
end

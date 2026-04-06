defmodule YtSearchWeb.NodeControllerChannelSlotTest do
  @moduledoc """
  Tests for NodeController channel slot upsert behavior with conflicting IDs and youtube_ids.
  """
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.ChannelSlot
  alias YtSearch.Data.ChannelSlotRepo

  import Ecto.Query

  setup do
    # Clean up any existing channel slots to ensure a clean state
    from(s in ChannelSlot) |> ChannelSlotRepo.delete_all()

    on_exit(fn ->
      System.delete_env("NODE_AUTH")
    end)

    :ok
  end

  # Helper to insert a channel slot directly without going through create/2
  defp insert_channel_slot!(id, youtube_id, opts \\ []) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    expires_at = Keyword.get(opts, :expires_at, NaiveDateTime.add(now, 1200, :second))
    keepalive = Keyword.get(opts, :keepalive, false)

    %ChannelSlot{
      id: id,
      youtube_id: youtube_id,
      expires_at: expires_at,
      used_at: now,
      keepalive: keepalive
    }
    |> ChannelSlotRepo.insert!()
  end

  # Helper to build minimal search_slot_data for the API
  defp build_search_slot_data(id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    expires_at = NaiveDateTime.add(now, 1200, :second)

    %{
      "id" => id,
      "query" => "test_query_#{id}",
      "slots_json" => "[]",
      "type" => "fetched",
      "result_type" => "text",
      "expires_at" => NaiveDateTime.to_iso8601(expires_at),
      "used_at" => NaiveDateTime.to_iso8601(now),
      "keepalive" => false,
      "inserted_at" => NaiveDateTime.to_iso8601(now),
      "updated_at" => NaiveDateTime.to_iso8601(now)
    }
  end

  describe "submit_search_slot with channel_slots having ID/youtube_id conflicts" do
    test "overwrites existing slot when new slot has same ID but different youtube_id", %{
      conn: conn
    } do
      System.put_env("NODE_AUTH", "test-secret-token")

      # Create an existing channel slot with ID 100 and youtube_id "channel_A"
      insert_channel_slot!(100, "channel_A")

      # Verify setup
      existing = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 100))
      assert existing != nil
      assert existing.youtube_id == "channel_A"

      # Now submit a new slot with same ID (100) but different youtube_id ("channel_B")
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      expires_at = NaiveDateTime.add(now, 1200, :second)

      payload = %{
        "search_slot_data" => build_search_slot_data(:rand.uniform(10000)),
        "video_slots" => [],
        "channel_slots" => [
          %{
            "id" => 100,
            "youtube_id" => "channel_B",
            "expires_at" => NaiveDateTime.to_iso8601(expires_at),
            "used_at" => NaiveDateTime.to_iso8601(now),
            "keepalive" => false,
            "inserted_at" => NaiveDateTime.to_iso8601(now),
            "updated_at" => NaiveDateTime.to_iso8601(now)
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", payload)

      resp = json_response(conn, 200)
      assert resp["status"] == "ok"

      # Verify: slot with ID 100 now has youtube_id "channel_B"
      updated_slot = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 100))
      assert updated_slot != nil
      assert updated_slot.youtube_id == "channel_B"

      # Verify: no slot with youtube_id "channel_A" exists anymore
      old_slot = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.youtube_id == "channel_A"))
      assert old_slot == nil
    end

    test "overwrites existing slot when new slot has same youtube_id but different ID", %{
      conn: conn
    } do
      System.put_env("NODE_AUTH", "test-secret-token")

      # Create an existing channel slot with youtube_id "channel_X" and ID 50
      original_id = 50
      insert_channel_slot!(original_id, "channel_X")

      # Verify setup
      existing = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.youtube_id == "channel_X"))
      assert existing != nil
      assert existing.id == original_id

      # Now submit a new slot with same youtube_id but different ID (200)
      new_id = 200

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      expires_at = NaiveDateTime.add(now, 1200, :second)

      payload = %{
        "search_slot_data" => build_search_slot_data(:rand.uniform(10000)),
        "video_slots" => [],
        "channel_slots" => [
          %{
            "id" => new_id,
            "youtube_id" => "channel_X",
            "expires_at" => NaiveDateTime.to_iso8601(expires_at),
            "used_at" => NaiveDateTime.to_iso8601(now),
            "keepalive" => false,
            "inserted_at" => NaiveDateTime.to_iso8601(now),
            "updated_at" => NaiveDateTime.to_iso8601(now)
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", payload)

      resp = json_response(conn, 200)
      assert resp["status"] == "ok"

      # Verify: slot with youtube_id "channel_X" now has ID 200
      updated_slot =
        ChannelSlotRepo.one(from(s in ChannelSlot, where: s.youtube_id == "channel_X"))

      assert updated_slot != nil
      assert updated_slot.id == new_id

      # Verify: no slot with the original ID exists anymore
      old_slot = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == ^original_id))
      assert old_slot == nil
    end

    test "handles multiple conflicting slots in single submission", %{conn: conn} do
      System.put_env("NODE_AUTH", "test-secret-token")

      # Setup: Create multiple existing channel slots
      # Slot 1: ID 300, youtube_id "existing_channel_1"
      insert_channel_slot!(300, "existing_channel_1")

      # Slot 2: ID 301, youtube_id "existing_channel_2"
      insert_channel_slot!(301, "existing_channel_2")

      # Verify setup
      slot1 = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 300))
      slot2 = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 301))
      assert slot1 != nil and slot1.youtube_id == "existing_channel_1"
      assert slot2 != nil and slot2.youtube_id == "existing_channel_2"

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      expires_at = NaiveDateTime.add(now, 1200, :second)

      # Submit new slots where:
      # - New slot A has ID 300 (conflicts with existing ID) but youtube_id "new_channel_A"
      # - New slot B has youtube_id "existing_channel_2" (conflicts with existing youtube_id) but ID 400
      payload = %{
        "search_slot_data" => build_search_slot_data(:rand.uniform(10000)),
        "video_slots" => [],
        "channel_slots" => [
          %{
            "id" => 300,
            "youtube_id" => "new_channel_A",
            "expires_at" => NaiveDateTime.to_iso8601(expires_at),
            "used_at" => NaiveDateTime.to_iso8601(now),
            "keepalive" => false,
            "inserted_at" => NaiveDateTime.to_iso8601(now),
            "updated_at" => NaiveDateTime.to_iso8601(now)
          },
          %{
            "id" => 400,
            "youtube_id" => "existing_channel_2",
            "expires_at" => NaiveDateTime.to_iso8601(expires_at),
            "used_at" => NaiveDateTime.to_iso8601(now),
            "keepalive" => true,
            "inserted_at" => NaiveDateTime.to_iso8601(now),
            "updated_at" => NaiveDateTime.to_iso8601(now)
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", payload)

      resp = json_response(conn, 200)
      assert resp["status"] == "ok"

      # Verify results:

      # 1. ID 300 now has youtube_id "new_channel_A" (old "existing_channel_1" is gone)
      slot_300 = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 300))
      assert slot_300 != nil
      assert slot_300.youtube_id == "new_channel_A"

      # 2. youtube_id "existing_channel_1" no longer exists
      old_channel_1 =
        ChannelSlotRepo.one(from(s in ChannelSlot, where: s.youtube_id == "existing_channel_1"))

      assert old_channel_1 == nil

      # 3. youtube_id "existing_channel_2" now has ID 400 (old ID 301 slot is gone)
      channel_2 =
        ChannelSlotRepo.one(from(s in ChannelSlot, where: s.youtube_id == "existing_channel_2"))

      assert channel_2 != nil
      assert channel_2.id == 400
      assert channel_2.keepalive == true

      # 4. Old ID 301 slot no longer exists
      old_slot_301 = ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 301))
      assert old_slot_301 == nil
    end

    test "handles submission where new slot conflicts on both ID and youtube_id with different existing slots",
         %{conn: conn} do
      System.put_env("NODE_AUTH", "test-secret-token")

      # Setup: Create two existing channel slots
      # Slot 1: ID 500, youtube_id "channel_alpha"
      insert_channel_slot!(500, "channel_alpha")

      # Slot 2: ID 501, youtube_id "channel_beta"
      insert_channel_slot!(501, "channel_beta")

      # Verify setup
      assert ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 500)) != nil
      assert ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 501)) != nil

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      expires_at = NaiveDateTime.add(now, 1200, :second)

      # Submit a new slot that has:
      # - ID 500 (same as slot 1)
      # - youtube_id "channel_beta" (same as slot 2)
      # This should delete BOTH existing slots
      payload = %{
        "search_slot_data" => build_search_slot_data(:rand.uniform(10000)),
        "video_slots" => [],
        "channel_slots" => [
          %{
            "id" => 500,
            "youtube_id" => "channel_beta",
            "expires_at" => NaiveDateTime.to_iso8601(expires_at),
            "used_at" => NaiveDateTime.to_iso8601(now),
            "keepalive" => false,
            "inserted_at" => NaiveDateTime.to_iso8601(now),
            "updated_at" => NaiveDateTime.to_iso8601(now)
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", payload)

      resp = json_response(conn, 200)
      assert resp["status"] == "ok"

      # Verify: only one slot exists now with ID 500 and youtube_id "channel_beta"
      all_slots = ChannelSlotRepo.all(from(s in ChannelSlot))
      assert length(all_slots) == 1

      slot = hd(all_slots)
      assert slot.id == 500
      assert slot.youtube_id == "channel_beta"

      # Both original slots should be gone
      assert ChannelSlotRepo.one(from(s in ChannelSlot, where: s.youtube_id == "channel_alpha")) ==
               nil

      assert ChannelSlotRepo.one(from(s in ChannelSlot, where: s.id == 501)) == nil
    end
  end
end

defmodule YtSearchWeb.ThumbnailerNodeTest do
  use YtSearchWeb.ConnCase, async: false

  alias YtSearch.{Slot, SearchSlot, Thumbnail}
  alias YtSearch.Test.Data

  import Tesla.Mock

  @piped_search_output File.read!("test/support/piped_outputs/urban_rescue_ranch_search.json")

  setup do
    # Mock thumbnail downloads
    mock_global(fn
      %{method: :get, url: "https://i.ytimg.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://yt3.ggpht.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://yt3.googleusercontent.com/" <> _} ->
        Data.png_response()

      %{method: :get, url: "https://i9.ytimg.com/" <> _} ->
        Data.png_response()
    end)

    :ok
  end

  describe "NodeController" do
    test "submit_search_slot endpoint accepts valid auth token", %{conn: conn} do
      # Set NODE_AUTH for thumbnailer
      System.put_env("NODE_AUTH", "test-secret-token")

      # Create test data
      slot = Slot.create("test_video_id", 3600)

      search_slot =
        SearchSlot.from_playlist(
          [%{type: "video", slot_id: "#{slot.id}", youtube_id: slot.youtube_id}],
          "youtube.com/test"
        )

      payload = %{
        "search_slot_data" => %{
          "id" => search_slot.id,
          "query" => search_slot.query,
          "slots_json" => search_slot.slots_json,
          "type" => "fetched",
          "expires_at" => NaiveDateTime.to_iso8601(search_slot.expires_at),
          "used_at" => NaiveDateTime.to_iso8601(search_slot.used_at),
          "keepalive" => search_slot.keepalive,
          "inserted_at" => NaiveDateTime.to_iso8601(search_slot.inserted_at),
          "updated_at" => NaiveDateTime.to_iso8601(search_slot.updated_at)
        },
        "video_slots" => [
          %{
            "id" => slot.id,
            "youtube_id" => slot.youtube_id,
            "video_duration" => slot.video_duration,
            "expires_at" => NaiveDateTime.to_iso8601(slot.expires_at),
            "used_at" => NaiveDateTime.to_iso8601(slot.used_at),
            "keepalive" => slot.keepalive,
            "inserted_at" => NaiveDateTime.to_iso8601(slot.inserted_at),
            "updated_at" => NaiveDateTime.to_iso8601(slot.updated_at)
          }
        ],
        "channel_slots" => []
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", payload)

      resp = json_response(conn, 200)
      assert resp["status"] == "ok"

      # Cleanup
      System.delete_env("NODE_AUTH")
    end

    test "submit_search_slot endpoint rejects invalid auth token", %{conn: conn} do
      System.put_env("NODE_AUTH", "test-secret-token")

      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", %{})

      resp = json_response(conn, 401)
      assert resp["error"] == "unauthorized"

      System.delete_env("NODE_AUTH")
    end

    test "submit_search_slot endpoint rejects missing auth", %{conn: conn} do
      System.put_env("NODE_AUTH", "test-secret-token")

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/search_slot", %{})

      resp = json_response(conn, 401)
      assert resp["error"] == "unauthorized"

      System.delete_env("NODE_AUTH")
    end

    @tag :slow
    test "submit_thumbnail endpoint triggers download", %{conn: conn} do
      System.put_env("NODE_AUTH", "test-secret-token")

      payload = %{
        "youtube_id" => "thumbnail_test_id",
        "thumbnail_url" => "https://i.ytimg.com/vi/test/maxresdefault.jpg"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/thumbnail", payload)

      resp = json_response(conn, 200)
      assert resp["status"] == "ok"

      # Wait a bit for async download
      Process.sleep(100)

      # Verify thumbnail was downloaded
      thumbnail = Thumbnail.fetch("thumbnail_test_id")
      assert thumbnail != nil
      assert thumbnail.id == "thumbnail_test_id"

      System.delete_env("NODE_AUTH")
    end

    test "submit_thumbnail endpoint rejects missing parameters", %{conn: _conn} do
      System.put_env("NODE_AUTH", "test-secret-token")

      # Missing thumbnail_url
      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/thumbnail", %{"youtube_id" => "test"})

      resp1 = json_response(conn1, 400)
      assert resp1["error"] == "missing youtube_id or thumbnail_url"

      # Missing youtube_id
      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer test-secret-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/node/thumbnail", %{"thumbnail_url" => "http://test.com"})

      resp2 = json_response(conn2, 400)
      assert resp2["error"] == "missing youtube_id or thumbnail_url"

      System.delete_env("NODE_AUTH")
    end
  end

  describe "ThumbnailerClient integration" do
    test "search with EXTERNAL_THUMBNAIL_NODE set triggers sync (fails gracefully if unreachable)",
         %{
           conn: conn
         } do
      # Set up thumbnailer environment (unreachable URL)
      System.put_env("EXTERNAL_THUMBNAIL_NODE", "http://unreachable-thumbnailer:9999")
      System.put_env("NODE_AUTH", "test-secret-token")

      mock(fn
        %{method: :get, url: "example.org/search" <> _whatever} ->
          json(Jason.decode!(@piped_search_output))
      end)

      # Search should still succeed even if thumbnailer sync fails
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v6/search?search=urban+rescue+ranch")

      resp_json = json_response(conn, 200)
      assert resp_json["slot_id"] != nil
      assert length(resp_json["search_results"]) > 0

      # Cleanup
      System.delete_env("EXTERNAL_THUMBNAIL_NODE")
      System.delete_env("NODE_AUTH")
    end

    test "search works normally when EXTERNAL_THUMBNAIL_NODE is not set", %{conn: conn} do
      # Ensure no thumbnailer configured
      System.delete_env("EXTERNAL_THUMBNAIL_NODE")

      mock(fn
        %{method: :get, url: "example.org/search" <> _whatever} ->
          json(Jason.decode!(@piped_search_output))
      end)

      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v6/search?search=urban+rescue+ranch")

      resp_json = json_response(conn, 200)
      assert resp_json["slot_id"] != nil
      assert length(resp_json["search_results"]) > 0
    end
  end

  describe "Full search -> atlas flow on thumbnailer" do
    test "search on main app, atlas on thumbnailer", %{conn: conn} do
      System.put_env("NODE_AUTH", "test-secret-token")
      System.put_env("EXTERNAL_THUMBNAIL_NODE", "http://thumbnailer:4000")

      mock(fn
        %{method: :get, url: "example.org/search" <> _whatever} ->
          json(Jason.decode!(@piped_search_output))

        # Mock the sync call to thumbnailer (simulate it calling back to itself)
        %{method: :post, url: "http://thumbnailer:4000/api/node/search_slot"} = request ->
          # Instead of mocking, actually call the NodeController
          {:ok, body} = Jason.decode(request.body)

          # Simulate thumbnailer receiving the sync
          build_conn()
          |> put_req_header("authorization", "Bearer test-secret-token")
          |> put_req_header("content-type", "application/json")
          |> post("/api/node/search_slot", body)

          %Tesla.Env{status: 200, body: Jason.encode!(%{"status" => "ok"})}
      end)

      # 1. Do search on main app
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v6/search?search=urban+rescue+ranch")

      resp_json = json_response(conn, 200)
      search_slot_id = resp_json["slot_id"]
      assert search_slot_id != nil

      # Wait for async thumbnail downloads
      Process.sleep(200)

      # 2. Request atlas (simulating request to thumbnailer)
      atlas_conn =
        build_conn()
        |> get("/a/6/at/#{search_slot_id}")

      assert atlas_conn.status == 200
      assert Plug.Conn.get_resp_header(atlas_conn, "content-type") == ["image/png"]

      # Verify it's a valid image
      temporary_path = Temp.path!()
      File.write!(temporary_path, atlas_conn.resp_body)
      YtSearch.AssertUtil.image(temporary_path)

      System.delete_env("EXTERNAL_THUMBNAIL_NODE")
      System.delete_env("NODE_AUTH")
    end
  end
end

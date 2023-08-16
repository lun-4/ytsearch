defmodule YtSearchWeb.VideoUnavailableTest do
  use YtSearchWeb.ConnCase, async: false
  import Tesla.Mock
  alias YtSearch.Test.Data
  alias YtSearch.Slot

  @test_youtube_id "DTDimRi2_TQ"
  @piped_video_output File.read!("test/support/piped_outputs/unavailable.json")

  setup do
    Data.default_global_mock()

    mock(fn
      %{method: :get, url: "example.org/streams/#{@test_youtube_id}"} ->
        json(Jason.decode!(@piped_video_output), status: 500)
    end)

    %{slot: Slot.create(@test_youtube_id, 0)}
  end

  test "it successfully gives out 404 on unavailable video for subtitle", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/2/sl/#{slot.id}")

    resp_json = json_response(conn, 200)
    assert resp_json["subtitle_data"] == nil
  end

  test "it successfully gives out 404 on unavailable video for mp4 link", %{
    conn: conn,
    slot: slot
  } do
    conn =
      conn
      |> get(~p"/a/2/sr/#{slot.id}")

    assert text_response(conn, 404) == "video unavailable"
  end
end

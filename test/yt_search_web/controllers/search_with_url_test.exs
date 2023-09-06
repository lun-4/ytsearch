defmodule YtSearchWeb.SearchWithURLTest do
  use YtSearchWeb.ConnCase, async: false
  import Tesla.Mock
  alias YtSearch.Test.Data

  @test_youtube_id "DTDimRi2_TQ"
  @piped_video_output File.read!("test/support/piped_outputs/video_streams.json")

  setup do
    Data.default_global_mock()

    mock(fn
      %{method: :get, url: "example.org/streams/#{@test_youtube_id}"} ->
        json(Jason.decode!(@piped_video_output))

      %{method: :get, url: "example.org/search" <> _} ->
        json(%{items: []})
    end)
  end

  @valid_test_cases [
    "youtu.be/#{@test_youtube_id}",
    "https://youtu.be/#{@test_youtube_id}",
    "http://youtu.be/#{@test_youtube_id}",
    "youtube.com/watch?v=#{@test_youtube_id}",
    "https://youtube.com/watch?v=#{@test_youtube_id}",
    "https://youtube.com/watch?v=#{@test_youtube_id}&t=666",
    "http://youtube.com/watch?v=#{@test_youtube_id}",
    "http://youtube.com/live/#{@test_youtube_id}",
    "youtube.com/live/#{@test_youtube_id}",
    "www.youtube.com/live/#{@test_youtube_id}",
    "https://youtube.com/live/#{@test_youtube_id}"
  ]

  @invalid_test_cases [
    "#{@test_youtube_id}",
    "youtube.com/#{@test_youtube_id}",
    "www.youtube.com/watch/?/v=#{@test_youtube_id}"
  ]

  test "it gets single video result" do
    @valid_test_cases
    |> Enum.map(fn case ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/2/s?q=#{case}")
    end)
    |> Enum.map(fn conn ->
      resp_json = json_response(conn, 200)
      assert length(resp_json["search_results"]) == 1
      first = resp_json["search_results"] |> Enum.at(0)
      assert first["youtube_id"] == @test_youtube_id
      assert first["description"] != nil
      assert first["title"] != nil
      assert first["channel_name"] != nil
    end)
  end

  test "it doesnt single video result on invalid format search" do
    @invalid_test_cases
    |> Enum.map(fn case ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/2/s?q=#{case}")
    end)
    |> Enum.map(fn conn ->
      resp_json = json_response(conn, 200)
      assert Enum.empty?(resp_json["search_results"])
    end)
  end
end

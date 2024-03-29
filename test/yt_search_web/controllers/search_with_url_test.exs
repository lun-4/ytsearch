defmodule YtSearchWeb.SearchWithURLTest do
  use YtSearchWeb.ConnCase, async: false
  import Tesla.Mock
  alias YtSearch.Test.Data

  @test_youtube_id "DTDimRi2_TQ"
  @test_playlist_id "mk5rw-dovj0YyywhqytCZ2rGKmk5rw-dovj0YyywhqytCZ2rGK"
  @piped_video_output File.read!("test/support/piped_outputs/video_streams.json")
  @piped_playlist_output File.read!("test/support/piped_outputs/unlisted_playlist.json")

  setup do
    Data.default_global_mock()
  end

  def video_mock do
    mock(fn
      %{method: :get, url: "example.org/streams/#{@test_youtube_id}"} ->
        json(Jason.decode!(@piped_video_output))

      %{method: :get, url: "example.org/search" <> _} ->
        json(%{items: []})
    end)
  end

  def playlist_mock do
    mock(fn
      %{method: :get, url: "example.org/playlists/#{@test_playlist_id}"} ->
        json(Jason.decode!(@piped_playlist_output))

      %{method: :get, url: "example.org/search" <> _} ->
        json(%{items: []})
    end)
  end

  @valid_test_cases [
    "youtu.be/#{@test_youtube_id}",
    "youtu.be/watch?v=#{@test_youtube_id}",
    "https://youtu.be/#{@test_youtube_id}",
    "https://youtu.be/#{@test_youtube_id}?si=19385719832",
    "http://youtu.be/#{@test_youtube_id}",
    "youtube.com/watch?v=#{@test_youtube_id}",
    "https://youtube.com/watch?v=#{@test_youtube_id}",
    "https://youtube.com/watch?v=#{@test_youtube_id}&t=666",
    "http://youtube.com/watch?v=#{@test_youtube_id}",
    "http://youtube.com/live/#{@test_youtube_id}",
    "youtube.com/live/#{@test_youtube_id}",
    "www.youtube.com/live/#{@test_youtube_id}",
    "https://youtube.com/live/#{@test_youtube_id}",
    "https://youtube.com/shorts/#{@test_youtube_id}"
  ]

  @invalid_test_cases [
    "#{@test_youtube_id}",
    "youtube.com/#{@test_youtube_id}",
    "www.youtube.com/watch/?/v=#{@test_youtube_id}",
    "youtu.be/#{@test_youtube_id |> String.slice(0, 10)}"
  ]

  test "it gets single video result" do
    video_mock()

    @valid_test_cases
    |> Enum.map(fn case ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=#{case}")
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
    video_mock()

    @invalid_test_cases
    |> Enum.map(fn case ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=#{case}")
    end)
    |> Enum.map(fn conn ->
      resp_json = json_response(conn, 200)
      assert Enum.empty?(resp_json["search_results"])
    end)
  end

  @valid_playlist_test_cases [
    "youtu.be/playlist/?list=#{@test_playlist_id}",
    "youtu.be/playlist/?a=b&c=d&list=#{@test_playlist_id}",
    "https://youtu.be/playlist?list=#{@test_playlist_id}",
    "https://youtu.be/playlist?list=#{@test_playlist_id}"
  ]

  @invalid_playlist_test_cases [
    "#{@test_playlist_id}",
    "youtube.com/#{@test_playlist_id}",
    "www.youtube.com/watch/?/v=#{@test_playlist_id}"
  ]

  test "it gets playlist result" do
    playlist_mock()

    @valid_playlist_test_cases
    |> Enum.map(fn case ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=#{case}")
    end)
    |> Enum.map(fn conn ->
      resp_json = json_response(conn, 200)
      assert length(resp_json["search_results"]) == 2
    end)
  end

  test "it doesnt resolve playlist urls on invalid format" do
    playlist_mock()

    @invalid_playlist_test_cases
    |> Enum.map(fn case ->
      Phoenix.ConnTest.build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/s?q=#{case}")
    end)
    |> Enum.map(fn conn ->
      resp_json = json_response(conn, 200)
      assert Enum.empty?(resp_json["search_results"])
    end)
  end
end

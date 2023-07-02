defmodule YtSearchWeb.SlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock
  alias YtSearch.Slot

  @youtube_id "Jouh2mdt1fI"

  test "it gets the mp4 url on quest useragents, supporting ttl", %{conn: conn} do
    with_mock(
      YtSearch.Youtube,
      fetch_mp4_link: [in_series([@youtube_id], [{:ok, "mp4.com"}, {:ok, "mp5.com"}])]
    ) do
      slot = Slot.from(@youtube_id)

      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == ["mp4.com"]

      link = YtSearch.Mp4Link.fetch_by_id(@youtube_id)
      assert link != nil

      link
      |> Ecto.Changeset.change(inserted_at: link.inserted_at |> NaiveDateTime.add(-5000, :second))
      |> YtSearch.Repo.update!()

      conn =
        build_conn()
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == ["mp5.com"]
    end
  end

  test "subtitles work", %{conn: conn, slot: slot} do
    with_mocks([
      {System, [:passthrough],
       cmd: fn _, args, _ ->
         output = File.read!("test/support/files/ytdlp_subtitle_output.txt")
         {output, 0}
       end},
      {File, [:passthrough],
       read: fn path ->
         cond do
           String.contains?(path, "Apple's new Mac Pro can't do THIS! [yI7fV88T8A0].en-orig.vtt") ->
             {:ok, "Among Us"}

           String.contains?(path, "Apple's new Mac Pro can't do THIS! [yI7fV88T8A0].en.vtt") ->
             {:ok, "Among Us 2"}

           true ->
             passthrough([path])
         end
       end}
    ]) do
      conn =
        conn
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v1/s/#{slot.id}")

      resp = json_response(conn, 200)

      assert resp["subtitle_data"] != nil
    end
  end
end

defmodule YtSearchWeb.SlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock
  alias YtSearch.Slot
  alias YtSearch.Subtitle
  alias YtSearch.Repo
  import Ecto.Query

  @youtube_id "Jouh2mdt1fI"

  setup_all do
    ets = :ets.new(:mock_call_counter, [:public])
    %{ets_table: ets}
  end

  setup do
    slot = Slot.from(@youtube_id)
    %{slot: slot}
  end

  @custom_expire (System.os_time(:second) + 3_600) |> to_string

  @run1 File.read!("test/support/files/stdout_ytdlp_geturl_dumpjson.txt")
        |> String.replace("1688360198", @custom_expire)
  @run1_url_result "https://rr2---sn-oxunxg8pjvn-gxjl.googlevideo.com/videoplayback?expire=#{@custom_expire}&ei=pgCiZNDVBe2pobIPiq6pqA8&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1003&id=o-ANdnakoQKlSGp-uvkmjmZa5oqJUed6hsUz7eS-e_g320&itag=22&source=youtube&requiressl=yes&mh=A0&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7kn7r&ms=au%2Crdu&mv=m&mvi=2&pl=52&initcwndbps=478750&spc=Ul2SqzJcCc2KHSrHFBWlfSlG7kQZPSM&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=339.057&lmt=1673716310924231&mt=1688338410&fvip=2&fexp=24007246%2C24363393%2C51000014&c=ANDROID&txp=5432434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIgYoYhyrDOKJLsyS1SzRqXRRM6Z4rkRE0RU6kWNwFqY38CIQCPdGAN2OCTyzj_AZdc7s5PyS9JjQqZFnSopbKbS6itpw%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRQIhALdIfWCgI3dyh6OyJaUp_Qx7P4-sAW8iVTHaC7dobJw8AiBGIcUd6UtnawUTDsDrjyn9yB8DPoJycpeuF-ZRDqB7Yw%3D%3D"
  @run2 @run1 |> String.replace(@run1_url_result, "https://mp5.com")

  test "it gets the mp4 url on quest useragents, supporting ttl", %{conn: conn, slot: slot} do
    with_mock(
      System,
      [:passthrough],
      cmd: [in_series([:_, :_], [{@run1, 0}, {@run2, 0}])]
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == [
               @run1_url_result
             ]

      link = YtSearch.Mp4Link.fetch_by_id(@youtube_id)
      assert link != nil

      link
      |> Ecto.Changeset.change(
        inserted_at: link.inserted_at |> NaiveDateTime.add(-100_000, :second)
      )
      |> YtSearch.Repo.update!()

      conn =
        build_conn()
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert get_resp_header(conn, "location") == ["https://mp5.com"]
    end
  end

  test "subtitles are cleaned when theyre too old", %{slot: slot} do
    subtitle = Subtitle.insert(@youtube_id, "latin-1", "lorem ipsum listen to jungle now")

    from(s in Subtitle, where: s.youtube_id == ^subtitle.youtube_id, select: s)
    |> Repo.update_all(
      set: [
        inserted_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-Subtitle.ttl_seconds() - 30_000_000)
      ]
    )

    [fetched | []] = Subtitle.fetch(@youtube_id)
    assert fetched.subtitle_data == subtitle.subtitle_data
    Subtitle.Cleaner.do_clean_subtitles()
    # should be empty now
    [] = Subtitle.fetch(@youtube_id)
  end

  test "subtitles work and are only fetched once", %{conn: conn, slot: slot, ets_table: table} do
    with_mocks([
      {System, [:passthrough],
       cmd: fn _, _ ->
         {"", 0}
       end,
       cmd: fn _, _, _ ->
         :timer.sleep(50)
         calls = :ets.update_counter(table, :ytdlp_cmd, 1, {:ytdlp_cmd, 0})

         if calls > 1 do
           {"called mock too much", 1}
         else
           output = File.read!("test/support/files/ytdlp_subtitle_output.txt")
           {output, 0}
         end
       end},
      {Path, [:passthrough],
       wildcard: fn "/tmp/yts-subtitles/#{@youtube_id}/*#{@youtube_id}*en*.vtt" ->
         ytdlp_calls = :ets.lookup(table, :ytdlp_cmd) |> Keyword.get(:ytdlp_cmd) || 0

         if ytdlp_calls > 0 do
           [
             "/tmp/yts-subtitles/#{@youtube_id}/Apple's new Mac Pro can't do THIS! [yI7fV88T8A0].en-orig.vtt",
             "/tmp/yts-subtitles/#{@youtube_id}/Apple's new Mac Pro can't do THIS! [yI7fV88T8A0].en-orig.vtt"
           ]
         else
           []
         end
       end},
      {File, [:passthrough],
       read: fn path ->
         [ytdlp_cmd: ytdlp_calls] = :ets.lookup(table, :ytdlp_cmd)

         if ytdlp_calls < 1 do
           {:error, :didnt_call_ytdlp}
         else
           case path do
             "/tmp/yts-subtitles/#{@youtube_id}/Apple's new Mac Pro can't do THIS! [yI7fV88T8A0].en-orig.vtt" ->
               {:ok, "Among Us"}

             "/tmp/yts-subtitles/#{@youtube_id}/Apple's new Mac Pro can't do THIS! [yI7fV88T8A0].en.vtt" ->
               {:ok, "Among Us 2"}

             _ ->
               {:error, :enoent}
           end
         end
       end}
    ]) do
      1..10
      |> Enum.map(fn _ ->
        Task.async(fn ->
          Phoenix.ConnTest.build_conn()
          |> put_req_header("user-agent", "UnityWebRequest")
          |> get(~p"/api/v1/s/#{slot.id}")
        end)
      end)
      |> Enum.map(fn task ->
        conn = Task.await(task)
        resp = json_response(conn, 200)
        assert resp["subtitle_data"] == "Among Us"
      end)
    end
  end

  @another_youtube_id "k2RuprlsXng"
  @even_another_youtube_id "D6enSGlTJYA"

  test "correctly rerolls ids" do
    :rand.seed({:exsss, [125_964_573_718_566_670 | 47_560_692_658_558_529]})

    slot = Slot.from(@another_youtube_id)
    assert slot.id == 71186

    # go with the same seed, causing it to go down the reroll route

    :rand.seed({:exsss, [125_964_573_718_566_670 | 47_560_692_658_558_529]})

    slot = Slot.from(@even_another_youtube_id)
    assert slot.id == 47635
  end
end

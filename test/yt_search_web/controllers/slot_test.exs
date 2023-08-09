defmodule YtSearchWeb.SlotTest do
  use YtSearchWeb.ConnCase, async: false
  import Mock
  alias YtSearch.Slot
  alias YtSearch.Subtitle
  alias YtSearch.Mp4Link
  alias YtSearch.Repo
  import Ecto.Query

  @youtube_id "Jouh2mdt1fI"

  setup_all do
    ets = :ets.new(:mock_call_counter, [:public])
    %{ets_table: ets}
  end

  setup do
    slot = Slot.create(@youtube_id, 3600)
    %{slot: slot}
  end

  @custom_expire (System.os_time(:second) + 3_600) |> to_string

  @run1 File.read!("test/support/files/youtube_video_url_dumpjson.json")
        |> String.replace("1689377943", @custom_expire)
  @expected_run1_url "https://rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com/videoplayback?expire=#{@custom_expire}&ei=N4ixZIvVI5K-wgTpnZnABQ&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1000&id=o-AG7Gp8Ck3IiSrq01gTvGOSgGEQXSgK4fIfRhUbEN6bG0&itag=22&source=youtube&requiressl=yes&mh=xI&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7knee&ms=au%2Crdu&mv=m&mvi=1&pl=48&initcwndbps=1032500&spc=Ul2Sqylj0XRoYEDnWvXXBHgndotsGrA&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=666.435&lmt=1689203297962924&mt=1689355996&fvip=2&fexp=24007246&c=ANDROID&txp=4432434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRQIgNOCrI8Fh8Mgn2alrFGPSW5CwMJBhZ1BPkVCoQwI_r3cCIQDOqaJpe0hHBly0McJUbXuJdmsSC4lzz0rDYJI_1BgLcQ%3D%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRgIhAMWZANXrZcmTWWbhCR83utfBM0K6gNMIm1QBL5hyHbqWAiEAoWhLkZ-7_Kiz__PWYbNch_fd69oUM68v18YJ-OEkiy4%3D"
  @run2 @run1 |> String.replace(@expected_run1_url, "https://mp5.com")

  @run1_r18 File.read!("test/support/files/youtube_video_url_dumpjson.json")
            |> String.replace("1689377943", @custom_expire)
            |> String.replace("\"age_limit\": 0", "\"age_limit\": 18")

  test "it gets the mp4 url on quest useragents, supporting ttl", %{conn: conn, slot: slot} do
    with_mock(
      :exec,
      run: [
        in_series([:_, :_], [{:ok, [stdout: [@run1]]}, {:ok, [stdout: [@run2]]}])
      ]
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               @expected_run1_url
             ]

      {:ok, link} = YtSearch.Mp4Link.fetch_by_id(@youtube_id)
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

  test "it always spits out mp4 redirect for /sr/", %{conn: conn, slot: slot} do
    with_mock(
      :exec,
      run: [
        in_series([:_, :_], [{:ok, [stdout: [@run1]]}])
      ]
    ) do
      conn =
        conn
        |> get(~p"/api/v1/sr/#{slot.id}")

      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               @expected_run1_url
             ]
    end
  end

  @run_stream File.read!("test/support/files/lofi_stream.json")
              |> String.replace("1689378318", @custom_expire)
  @expected_run_stream_url "https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/#{@custom_expire}/ei/romxZLXCOoOF1sQPn9qkoAc/ip/2804:14d:5492:8fe8::1000/id/jfKfPfyJRdk.2/itag/96/source/yt_live_broadcast/requiressl/yes/ratebypass/yes/live/1/sgoap/gir%3Dyes%3Bitag%3D140/sgovp/gir%3Dyes%3Bitag%3D137/hls_chunk_host/rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com/playlist_duration/30/manifest_duration/30/spc/Ul2Sq66okm6aYvjhYIzLhVAacySq1KM/vprv/1/playlist_type/DVR/initcwndbps/1015000/mh/rr/mm/44/mn/sn-oxunxg8pjvn-gxjl/ms/lva/mv/m/mvi/1/pl/48/dover/11/pacing/0/keepalive/yes/fexp/24007246/beids/24350018/mt/1689356439/sparams/expire,ei,ip,id,itag,source,requiressl,ratebypass,live,sgoap,sgovp,playlist_duration,manifest_duration,spc,vprv,playlist_type/sig/AOq0QJ8wRgIhAObgGmA9jBsVLvxoQWsTgf5UnFnYaqHKv-oh5aXe_N7MAiEArz89GleotjzGD3A8PElTj_2pGP9HN6AIkZDJeo2nwnI%3D/lsparams/hls_chunk_host,initcwndbps,mh,mm,mn,ms,mv,mvi,pl/lsig/AG3C_xAwRQIhAN2uSS_Z-NVkxLcSm2iWnuS9sd6_rZ3SHBy_uni7rERHAiAyUvULpqCSKBKbGp5bJXYF5eSkfrnRw9UyAzgawfwbqw%3D%3D/playlist/index.m3u8"

  test "it gets m3u8 url on streams", %{conn: conn, slot: slot} do
    with_mock(
      :exec,
      run: [
        in_series([:_, :_], [{:ok, [stdout: [@run_stream]]}])
      ]
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert conn.status == 302

      assert get_resp_header(conn, "location") == [
               @expected_run_stream_url
             ]
    end
  end

  test "it gives 404 on unknown slot ids", %{conn: conn, slot: slot} do
    # i really dont want this test to fail because the generated test
    # slot clashes with a hardcoded one here
    {:ok, unknown_id} = YtSearch.SlotUtilities.find_available_slot_id(YtSearch.Slot)

    conn =
      conn
      |> get(~p"/a/1/sl/#{unknown_id}")

    assert conn.status == 404

    conn =
      conn
      |> get(~p"/a/1/sl/#{unknown_id}")

    assert conn.status == 404
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
    Subtitle.Cleaner.tick()
    # should be empty now
    [] = Subtitle.fetch(@youtube_id)
  end

  import Tesla.Mock

  test "subtitles work and are only fetched once", %{conn: conn, slot: slot, ets_table: table} do
    mock_global(fn
      %{method: :get, url: "example.org/streams/#{@youtube_id}"} ->
        :timer.sleep(50)
        calls = :ets.update_counter(table, :ytdlp_cmd, 1, {:ytdlp_cmd, 0})

        unless calls > 1 do
          json(%{
            "subtitles" => [
              %{
                "url" =>
                  "https://pipedproxy-cdg.kavin.rocks/api/timedtext?v=#{@youtube_id}&ei=k_TSZKi2ItWMobIPs7aF6AQ&caps=asr&opi=112496729&xoaf=5&lang=en&fmt=vtt&host=youtube.example.org",
                "mimeType" => "text/vtt",
                "name" => "English",
                "code" => "en",
                "autoGenerated" => true
              }
            ]
          })
        else
          %Tesla.Env{status: 500, body: "called mock too much"}
        end

      %{
        method: :get,
        url: "https://youtube.example.org/api/timedtext/?v=#{@youtube_id}" <> _rest
      } ->
        %Tesla.Env{status: 200, body: "Among Us"}

      %{
        method: :get,
        url: "https://youtube.example.org" <> _rest
      } ->
        # TODO fix this so it uses the proper prefix
        %Tesla.Env{status: 200, body: "Among Us"}
    end)

    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Phoenix.ConnTest.build_conn()
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v1/s/#{slot.id}")
        |> json_response(200)
      end)
    end)
    |> Enum.map(fn task ->
      resp = Task.await(task)
      assert resp["subtitle_data"] == "Among Us"
    end)
  end

  @another_youtube_id "k2RuprlsXng"
  @even_another_youtube_id "D6enSGlTJYA"

  test "correctly rerolls ids" do
    :rand.seed({:exsss, [125_964_573_718_566_670 | 47_560_692_658_558_529]})

    slot = Slot.create(@another_youtube_id, 3600)
    assert slot.id == 71186

    # go with the same seed, causing it to go down the reroll route

    :rand.seed({:exsss, [125_964_573_718_566_670 | 47_560_692_658_558_529]})

    slot = Slot.create(@even_another_youtube_id, 3600)
    assert slot.id == 47635
  end

  test "it removes links from db that are already expired", %{slot: slot} do
    link =
      Mp4Link.insert(
        "abcdef",
        "https://freeeee--mp5.net",
        DateTime.to_unix(DateTime.utc_now()) - Mp4Link.ttl_seconds() - 1,
        %{}
      )

    # assert its still on db
    from_db = Repo.one!(from s in Mp4Link, where: s.youtube_id == ^link.youtube_id, select: s)
    assert from_db.youtube_id == link.youtube_id

    YtSearch.Mp4Link.Janitor.tick()
    assert Repo.one(from s in Mp4Link, where: s.youtube_id == ^link.youtube_id, select: s) == nil
  end

  test "it removes slots from db that are already expired", %{slot: slot} do
    slot
    |> Ecto.Changeset.change(
      inserted_at: slot.inserted_at |> NaiveDateTime.add(-Slot.max_ttl(), :second),
      inserted_at_v2: slot.inserted_at_v2 - Slot.max_ttl()
    )
    |> Repo.update!()

    assert Slot.fetch_by_id(slot.id) == nil

    # assert its still on db
    from_db = Repo.one!(from s in Slot, where: s.id == ^slot.id, select: s)
    assert from_db.id == slot.id

    YtSearch.Slot.Janitor.tick()
    assert Repo.one(from s in Slot, where: s.id == ^slot.id, select: s) == nil
  end

  test "it does not fetch age restricted videos", %{conn: conn, slot: slot} do
    with_mock(
      :exec,
      run: [
        in_series([:_, :_], [{:ok, [stdout: [@run1_r18]]}])
      ]
    ) do
      conn =
        conn
        |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
        |> get(~p"/api/v1/s/#{slot.id}")

      assert conn.status == 404
      assert conn.resp_body == "age restricted video (18)"

      {:ok, link} = YtSearch.Mp4Link.fetch_by_id(@youtube_id)
      assert link != nil

      assert link |> YtSearch.Mp4Link.meta() |> Map.get("age_limit") == 18
    end
  end

  test "it gives 404 on invalid youtube ids", %{conn: conn, slot: slot} do
    with_mock(
      :exec,
      run: [
        in_series([:_, :_], [
          {:error,
           [
             exit_status: 256,
             stdout: [],
             stderr: [
               "[youtube] zOfKfdXQTVU: Video unavailable. This video is no longer available because the YouTube account associated with this video has been terminated."
             ]
           ]}
        ])
      ]
    ) do
      1..10
      |> Enum.each(fn _ ->
        conn =
          conn
          |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
          |> get(~p"/api/v1/s/#{slot.id}")

        assert conn.status == 404
        assert conn.resp_body == "video unavailable"
      end)
    end
  end
end

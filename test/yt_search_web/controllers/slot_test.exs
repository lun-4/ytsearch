defmodule YtSearchWeb.SlotTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.Subtitle
  alias YtSearch.Mp4Link
  alias YtSearch.Repo
  import Ecto.Query
  alias YtSearch.Test.Data

  @youtube_id "Jouh2mdt1fI"

  setup_all do
    ets = :ets.new(:mock_call_counter, [:public])
    %{ets_table: ets}
  end

  setup do
    slot = Slot.create(@youtube_id, 3600)
    stop_metadata_workers(slot.youtube_id)
    %{slot: slot}
  end

  @custom_expire (System.os_time(:second) + 3_600) |> to_string

  @run1 File.read!("test/support/piped_outputs/video_streams.json")
        |> String.replace("1691627905", @custom_expire)

  @expected_run1_url "https://rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com/videoplayback?expire=#{@custom_expire}&ei=Id3TZI2vOZ-lobIP_dmBiA4&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1001&id=o-AHJX6AwsW-zQGeS4Eyu1Bdv-yjYJr1bEu-We0EmP4NDb&itag=22&source=youtube&requiressl=yes&mh=xI&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7knee&ms=au%2Crdu&mv=m&mvi=1&pl=52&initcwndbps=835000&spc=UWF9f3ylca2q7Fjk8ujpSFMzTN3TUXs&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=666.435&lmt=1689626995182173&mt=1691606033&fvip=2&fexp=24007246%2C24362688&c=ANDROID&txp=5532434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRgIhAPypX1tk8JHpuo_QPe9KKVaiy-hbIBIXyq5qBBg963rzAiEAsnlp-AkDLpOmwhcgCQ1TKRrs-EtMl230VM_9SbNGg14%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRAIgP3rzSh2MwDq2ZxW1Pcgfcf-pki_ahrDfZ1HFz4_5CpgCIHwqgkD-lup0L9EpoGyYEWjtM4XQEJjbppRu1aPaXV2A&cpn=iZTa_BP8GjO4tg7g&host=rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com"
  @run1_original_url "https://pipedproxy-cdg.kavin.rocks/videoplayback?expire=#{@custom_expire}&ei=Id3TZI2vOZ-lobIP_dmBiA4&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1001&id=o-AHJX6AwsW-zQGeS4Eyu1Bdv-yjYJr1bEu-We0EmP4NDb&itag=22&source=youtube&requiressl=yes&mh=xI&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7knee&ms=au%2Crdu&mv=m&mvi=1&pl=52&initcwndbps=835000&spc=UWF9f3ylca2q7Fjk8ujpSFMzTN3TUXs&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=666.435&lmt=1689626995182173&mt=1691606033&fvip=2&fexp=24007246%2C24362688&c=ANDROID&txp=5532434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRgIhAPypX1tk8JHpuo_QPe9KKVaiy-hbIBIXyq5qBBg963rzAiEAsnlp-AkDLpOmwhcgCQ1TKRrs-EtMl230VM_9SbNGg14%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRAIgP3rzSh2MwDq2ZxW1Pcgfcf-pki_ahrDfZ1HFz4_5CpgCIHwqgkD-lup0L9EpoGyYEWjtM4XQEJjbppRu1aPaXV2A&cpn=iZTa_BP8GjO4tg7g&host=rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com"
  @run2 @run1 |> String.replace(@run1_original_url, "https://mp5.com")

  defp stop_metadata_workers(youtube_id) do
    with [{worker, :self}] <- Registry.lookup(YtSearch.MetadataWorkers, youtube_id),
         true <- Process.alive?(worker) do
      GenServer.stop(worker, {:shutdown, :test_request})
    end

    with [{worker, :self}] <-
           Registry.lookup(YtSearch.MetadataExtractors, {:subtitles, youtube_id}),
         true <- Process.alive?(worker) do
      GenServer.stop(worker, {:shutdown, :test_request})
    end

    with [{worker, :self}] <-
           Registry.lookup(YtSearch.MetadataExtractors, {:mp4_link, youtube_id}),
         true <- Process.alive?(worker) do
      GenServer.stop(worker, {:shutdown, :test_request})
    end
  end

  test "it gets the mp4 url on quest useragents, supporting ttl", %{
    conn: conn,
    slot: slot,
    ets_table: table
  } do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams/#{@youtube_id}"} ->
        calls = :ets.update_counter(table, :ytdlp_cmd_2, 1, {:ytdlp_cmd_2, 0})

        Tesla.Mock.json(
          case calls do
            1 -> @run1
            2 -> @run2
          end
          |> Jason.decode!()
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
      |> get(~p"/api/v2/s/#{slot.id}")

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

    stop_metadata_workers(slot.youtube_id)

    conn =
      build_conn()
      |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
      |> get(~p"/api/v2/s/#{slot.id}")

    assert get_resp_header(conn, "location") == ["https://mp5.com"]
  end

  test "it always spits out mp4 redirect for /sr/", %{conn: conn, slot: slot} do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams" <> _} ->
        Tesla.Mock.json(
          @run1
          |> Jason.decode!()
        )
    end)

    conn =
      conn
      |> get(~p"/api/v2/sr/#{slot.id}")

    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             @expected_run1_url
           ]
  end

  @run_stream File.read!("test/support/piped_outputs/lofi_stream.json")
              |> String.replace("1691635330", @custom_expire)
  @expected_stream_url "https://manifest.googlevideo.com/api/manifest/hls_variant/expire/#{@custom_expire}/ei/IvrTZLKgGf_Y1sQPk4KOuAE/ip/2804%3A14d%3A5492%3A8fe8%3A%3A1001/id/jfKfPfyJRdk.2/source/yt_live_broadcast/requiressl/yes/hfr/1/playlist_duration/3600/manifest_duration/3600/demuxed/1/maudio/1/vprv/1/go/1/pacing/0/nvgoi/1/short_key/1/ncsapi/1/keepalive/yes/fexp/24007246%2C51000023/dover/13/itag/0/playlist_type/DVR/sparams/expire%2Cei%2Cip%2Cid%2Csource%2Crequiressl%2Chfr%2Cplaylist_duration%2Cmanifest_duration%2Cdemuxed%2Cmaudio%2Cvprv%2Cgo%2Citag%2Cplaylist_type/sig/AOq0QJ8wRQIhANBnLbXAZIDegOLck5OxexbCOmLLVMKOtqukyUpwVnr1AiAHdQByc0Hm-MPN26SmyYflKk9LA905ahxukvjccfzR5w%3D%3D/file/index.m3u8?host=manifest.googlevideo.com"

  test "it gets m3u8 url on streams", %{conn: conn, slot: slot} do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams" <> _} ->
        Tesla.Mock.json(
          @run_stream
          |> Jason.decode!()
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
      |> get(~p"/api/v2/s/#{slot.id}")

    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             @expected_stream_url
           ]
  end

  test "it gives 404 on unknown slot ids", %{conn: conn} do
    # i really dont want this test to fail because the generated test
    # slot clashes with a hardcoded one here
    {:ok, unknown_id} = YtSearch.SlotUtilities.find_available_slot_id(YtSearch.Slot)

    conn =
      conn
      |> get(~p"/a/2/sl/#{unknown_id}")

    assert conn.status == 404

    conn =
      conn
      |> get(~p"/a/2/sl/#{unknown_id}")

    assert conn.status == 404
  end

  test "subtitles are cleaned when theyre too old" do
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

  test "subtitles work and are only fetched once", %{slot: slot, ets_table: table} do
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
        url: "https://youtube.example.org/api/timedtext?v=#{@youtube_id}" <> _rest
      } ->
        %Tesla.Env{status: 200, body: "Among Us"}
    end)

    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Phoenix.ConnTest.build_conn()
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v2/s/#{slot.id}")
        |> json_response(200)
      end)
    end)
    |> Enum.map(fn task ->
      resp = Task.await(task)
      assert resp["subtitle_data"] == "Among Us"
    end)
  end

  test "links work under pressure and are only fetched once", %{slot: slot, ets_table: table} do
    mock_global(fn
      %{method: :get, url: "example.org/streams/#{@youtube_id}"} ->
        # fake work
        :timer.sleep(50)
        calls = :ets.update_counter(table, :ytdlp_cmd_streams, 1, {:ytdlp_cmd_streams, 0})

        unless calls > 1 do
          json(%{
            "hls" => "awooga",
            "livestream" => true,
            "videoStreams" => []
          })
        else
          %Tesla.Env{status: 500, body: "called mock too much"}
        end
    end)

    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Phoenix.ConnTest.build_conn()
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/api/v2/sr/#{slot.id}")
      end)
    end)
    |> Enum.map(fn task ->
      conn = Task.await(task)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["awooga"]
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

  test "it removes links from db that are already expired" do
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

  test "it gives 200 on invalid youtube ids", %{conn: conn, slot: slot} do
    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams" <> _} ->
        json(
          %{
            error: "alkssdjlasjd",
            message: "Video unavailable"
          },
          status: 500
        )
    end)

    conn =
      conn
      |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
      |> get(~p"/api/v2/s/#{slot.id}")

    assert get_resp_header(conn, "yts-failure-code") == ["E01"]
    assert conn.status == 200
    assert response_content_type(conn, :mp4)
  end
end

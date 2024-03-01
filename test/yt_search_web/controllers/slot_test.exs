defmodule YtSearchWeb.SlotTest do
  alias YtSearch.Data.LinkRepo
  alias YtSearch.Data.SubtitleRepo
  alias YtSearch.Data.SlotRepo
  use YtSearchWeb.ConnCase, async: false
  require Logger
  alias YtSearch.Slot
  alias YtSearch.Subtitle
  alias YtSearch.Mp4Link
  import Ecto.Query
  alias YtSearch.Test.Data

  @youtube_id "Jouh2mdt1fI"

  setup_all do
    ets = :ets.new(:mock_call_counter, [:public])
    %{ets_table: ets}
  end

  setup do
    slot = Slot.create(@youtube_id, 3600)

    on_exit(fn ->
      stop_metadata_workers(slot.youtube_id)
    end)

    %{slot: slot}
  end

  defp insert_slot(attrs \\ []) do
    Factory.Slot.insert(:slot, attrs, on_conflict: :replace_all)
  end

  @custom_expire (System.os_time(:second) + 3_600) |> to_string

  @run1 File.read!("test/support/piped_outputs/video_streams.json")
        |> String.replace("1691627905", @custom_expire)

  @expected_run1_url "https://rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com/videoplayback?expire=#{@custom_expire}&ei=Id3TZI2vOZ-lobIP_dmBiA4&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1001&id=o-AHJX6AwsW-zQGeS4Eyu1Bdv-yjYJr1bEu-We0EmP4NDb&itag=22&source=youtube&requiressl=yes&mh=xI&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7knee&ms=au%2Crdu&mv=m&mvi=1&pl=52&initcwndbps=835000&spc=UWF9f3ylca2q7Fjk8ujpSFMzTN3TUXs&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=666.435&lmt=1689626995182173&mt=1691606033&fvip=2&fexp=24007246%2C24362688&c=ANDROID&txp=5532434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRgIhAPypX1tk8JHpuo_QPe9KKVaiy-hbIBIXyq5qBBg963rzAiEAsnlp-AkDLpOmwhcgCQ1TKRrs-EtMl230VM_9SbNGg14%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRAIgP3rzSh2MwDq2ZxW1Pcgfcf-pki_ahrDfZ1HFz4_5CpgCIHwqgkD-lup0L9EpoGyYEWjtM4XQEJjbppRu1aPaXV2A&cpn=iZTa_BP8GjO4tg7g&host=rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com"
  @run1_original_url "https://pipedproxy-cdg.kavin.rocks/videoplayback?expire=#{@custom_expire}&ei=Id3TZI2vOZ-lobIP_dmBiA4&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1001&id=o-AHJX6AwsW-zQGeS4Eyu1Bdv-yjYJr1bEu-We0EmP4NDb&itag=22&source=youtube&requiressl=yes&mh=xI&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7knee&ms=au%2Crdu&mv=m&mvi=1&pl=52&initcwndbps=835000&spc=UWF9f3ylca2q7Fjk8ujpSFMzTN3TUXs&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=666.435&lmt=1689626995182173&mt=1691606033&fvip=2&fexp=24007246%2C24362688&c=ANDROID&txp=5532434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRgIhAPypX1tk8JHpuo_QPe9KKVaiy-hbIBIXyq5qBBg963rzAiEAsnlp-AkDLpOmwhcgCQ1TKRrs-EtMl230VM_9SbNGg14%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRAIgP3rzSh2MwDq2ZxW1Pcgfcf-pki_ahrDfZ1HFz4_5CpgCIHwqgkD-lup0L9EpoGyYEWjtM4XQEJjbppRu1aPaXV2A&cpn=iZTa_BP8GjO4tg7g&host=rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com"
  @run2 @run1 |> String.replace(@run1_original_url, "https://mp5.com")

  defp stop_metadata_workers(_youtube_id) do
    DynamicSupervisor.which_children(YtSearch.MetadataSupervisor)
    |> Enum.each(fn {_id, child, _type, _modules} ->
      DynamicSupervisor.terminate_child(YtSearch.MetadataSupervisor, child)
    end)
  end

  test "it gets the mp4 url on quest useragents, supporting ttl", %{
    conn: conn,
    ets_table: table
  } do
    slot = insert_slot()

    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams/" <> wanted_youtube_id} = env ->
        if wanted_youtube_id == slot.youtube_id do
          calls = :ets.update_counter(table, :ytdlp_cmd_2, 1, {:ytdlp_cmd_2, 0})

          Tesla.Mock.json(
            case calls do
              1 -> @run1
              2 -> @run2
            end
            |> Jason.decode!()
          )
        else
          # ignore requests not to the generated slot
          env
        end
    end)

    conn =
      conn
      # |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
      |> get(~p"/a/5/sr/#{slot.id}")

    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             @expected_run1_url
           ]

    link = YtSearch.Mp4Link.fetch_by_id(slot.youtube_id)
    assert link != nil

    link
    |> Ecto.Changeset.change(
      inserted_at: link.inserted_at |> NaiveDateTime.add(-100_000, :second)
    )
    |> LinkRepo.update!()

    # instead of stopping, just unregister them both
    [{worker, :self}] = Registry.lookup(YtSearch.MetadataWorkers, slot.youtube_id)
    :ok = GenServer.call(worker, :unregister)
    [] = Registry.lookup(YtSearch.MetadataWorkers, slot.youtube_id)

    [{extractor, :self}] =
      Registry.lookup(YtSearch.MetadataExtractors, {:mp4_link, slot.youtube_id})

    :ok = GenServer.call(extractor, :unregister)

    [] =
      Registry.lookup(YtSearch.MetadataExtractors, {:mp4_link, slot.youtube_id})

    conn =
      build_conn()
      |> put_req_header("user-agent", "stagefright/1.2 (Linux;Android 12)")
      |> get(~p"/a/5/sr/#{slot.id}")

    assert get_resp_header(conn, "location") == ["https://mp5.com"]

    # as i still hold a pid of the link, i can fetch it again and it should give the old url
    {:ok, link} = YtSearch.MetadataExtractor.Worker.mp4_link(extractor)
    assert link.mp4_link == @expected_run1_url
  end

  test "it always spits out mp4 redirect for /sr/", %{conn: conn} do
    slot = insert_slot()

    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams" <> _} ->
        Tesla.Mock.json(
          @run1
          |> Jason.decode!()
        )
    end)

    conn =
      conn
      |> get(~p"/api/v5/sr/#{slot.id}")

    assert conn.status == 302

    assert get_resp_header(conn, "location") == [
             @expected_run1_url
           ]
  end

  @run_stream File.read!("test/support/piped_outputs/lofi_stream.json")
              |> String.replace("1691635330", @custom_expire)
  # @expected_stream_url "https://manifest.googlevideo.com/api/manifest/hls_variant/expire/#{@custom_expire}/ei/IvrTZLKgGf_Y1sQPk4KOuAE/ip/2804%3A14d%3A5492%3A8fe8%3A%3A1001/id/jfKfPfyJRdk.2/source/yt_live_broadcast/requiressl/yes/hfr/1/playlist_duration/3600/manifest_duration/3600/demuxed/1/maudio/1/vprv/1/go/1/pacing/0/nvgoi/1/short_key/1/ncsapi/1/keepalive/yes/fexp/24007246%2C51000023/dover/13/itag/0/playlist_type/DVR/sparams/expire%2Cei%2Cip%2Cid%2Csource%2Crequiressl%2Chfr%2Cplaylist_duration%2Cmanifest_duration%2Cdemuxed%2Cmaudio%2Cvprv%2Cgo%2Citag%2Cplaylist_type/sig/AOq0QJ8wRQIhANBnLbXAZIDegOLck5OxexbCOmLLVMKOtqukyUpwVnr1AiAHdQByc0Hm-MPN26SmyYflKk9LA905ahxukvjccfzR5w%3D%3D/file/index.m3u8?host=manifest.googlevideo.com"

  test "it redirects to youtube on livestreams", %{conn: conn} do
    slot = insert_slot(type: 1)

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
      |> get(~p"/a/5/sr/#{slot.id}")

    assert conn.status == 302

    assert get_resp_header(conn, "location") == ["https://youtube.com/watch?v=#{slot.youtube_id}"]
  end

  test "it gives 404 on unknown slot ids", %{conn: conn} do
    # i really dont want this test to fail because the generated test
    # slot clashes with a hardcoded one here
    {:ok, unknown_id} = YtSearch.SlotUtilities.generate_id_v3(YtSearch.Slot)

    conn =
      conn
      |> get(~p"/a/5/sl/#{unknown_id}")

    assert conn.status == 404

    conn =
      conn
      |> get(~p"/a/5/sl/#{unknown_id}")

    assert conn.status == 404
  end

  test "subtitles are cleaned when theyre too old", %{slot: slot} do
    subtitle = Subtitle.insert(slot.youtube_id, "latin-1", "lorem ipsum listen to jungle now")
    _ = Subtitle.insert(slot.youtube_id, "latin-1", "lorem ipsum listen to jungle now")
    _ = Subtitle.insert(slot.youtube_id, "latin-1", "lorem ipsum listen to jungle now")
    _ = Subtitle.insert(slot.youtube_id, "latin-1", "lorem ipsum listen to jungle now")

    from(s in Subtitle, where: s.youtube_id == ^subtitle.youtube_id, select: s)
    |> SubtitleRepo.update_all(
      set: [
        inserted_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-Subtitle.ttl_seconds() - 30_000_000)
      ]
    )

    [fetched | _] = Subtitle.fetch(slot.youtube_id)
    assert fetched.subtitle_data == subtitle.subtitle_data
    Subtitle.Cleaner.tick()
    # should be empty now
    [] = Subtitle.fetch(slot.youtube_id)
  end

  alias YtSearch.Sponsorblock.Segments

  test "segments are cleaned when theyre too old", %{slot: slot} do
    segments = Segments.insert(slot.youtube_id, [])

    from(s in Segments, where: s.youtube_id == ^segments.youtube_id, select: s)
    |> YtSearch.Data.SponsorblockRepo.update_all(
      set: [
        inserted_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-Segments.ttl_seconds() - 30_000_000)
      ]
    )

    fetched = Segments.fetch(slot.youtube_id)
    assert fetched.segments_json == segments.segments_json
    Segments.Cleaner.tick()
    nil = Segments.fetch(slot.youtube_id)
  end

  import Tesla.Mock

  test "metadata works and are only fetched once", %{ets_table: table} do
    slot = insert_slot()

    mock_global(fn
      %{method: :get, url: "sb.example.org/api/skipSegments?" <> query} = env ->
        query_args = query |> URI.decode_query()
        youtube_id = query_args |> Map.get("videoID")
        categories = query_args |> Map.get("categories") |> Jason.decode!() |> MapSet.new()

        correct_categories? =
          MapSet.difference(
            categories,
            YtSearch.Sponsorblock.categories() |> MapSet.new()
          )
          |> Enum.count()
          |> then(fn
            0 -> true
            _ -> false
          end)

        if youtube_id == slot.youtube_id and correct_categories? do
          :timer.sleep(50)
          calls = :ets.update_counter(table, :segments_cmd, 1, {:segments_cmd, 0})

          unless calls > 1 do
            json([
              %{
                "category" => "intro",
                "actionType" => "skip",
                "segment" => [
                  0,
                  1.925
                ],
                "UUID" => "24950dd1f8dc6bacac09a9bba19fee28064e2cf94101b4ec0e2003e2199ef7f57",
                "videoDuration" => 1626.561,
                "locked" => 0,
                "votes" => 0,
                "description" => ""
              },
              %{
                "category" => "sponsor",
                "actionType" => "skip",
                "segment" => [
                  90.343,
                  132.37
                ],
                "UUID" => "94cb65e5148e662bb9b8aebfe14948fec4e2624e49f0c847d9591c4a12b2fa187",
                "videoDuration" => 1626.561,
                "locked" => 1,
                "votes" => 10,
                "description" => ""
              }
            ])
          else
            %Tesla.Env{status: 500, body: "called mock too much"}
          end
        else
          Logger.warning("mock: sb.example.org called with #{youtube_id}, not #{slot.youtube_id}")
          env
        end

      %{method: :get, url: "example.org/streams/" <> youtube_id} = env ->
        if youtube_id == slot.youtube_id do
          :timer.sleep(50)
          calls = :ets.update_counter(table, :ytdlp_cmd, 1, {:ytdlp_cmd, 0})

          unless calls > 1 do
            json(%{
              "subtitles" => [
                %{
                  "url" =>
                    "https://pipedproxy-cdg.kavin.rocks/api/timedtext?v=#{slot.youtube_id}&ei=k_TSZKi2ItWMobIPs7aF6AQ&caps=asr&opi=112496729&xoaf=5&lang=en&fmt=vtt&host=youtube.example.org",
                  "mimeType" => "text/vtt",
                  "name" => "English",
                  "code" => "en",
                  "autoGenerated" => true
                },
                %{
                  "url" =>
                    "https://pipedproxy-cdg.kavin.rocks/api/timedtext?v=#{slot.youtube_id}ORIG&ei=k_TSZKi2ItWMobIPs7aF6AQ&caps=asr&opi=112496729&xoaf=5&lang=en&fmt=vtt&host=youtube.example.org",
                  "mimeType" => "text/vtt",
                  "name" => "English",
                  "code" => "en",
                  "autoGenerated" => false
                }
              ],
              "chapters" => [
                %{
                  "title" => "chhaslkfh lkjgflj",
                  "start" => 0
                },
                %{
                  "title" => "chhaslkfh lkjgflj gjksdjg",
                  "start" => 100
                }
              ]
            })
          else
            %Tesla.Env{status: 500, body: "called mock too much"}
          end
        else
          env
        end

      %{
        method: :get,
        url: "https://youtube.example.org/api/timedtext?v=" <> rest
      } = env ->
        [youtube_id | _rest] = String.split(rest, "&")

        cond do
          youtube_id == slot.youtube_id ->
            %Tesla.Env{status: 200, body: "Among Us"}

          youtube_id == slot.youtube_id <> "ORIG" ->
            %Tesla.Env{status: 200, body: "Among Us ORIGINAL"}

          true ->
            require Logger
            Logger.warning("invalid ytid #{youtube_id}")
            env
        end
    end)

    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Phoenix.ConnTest.build_conn()
        |> put_req_header("user-agent", "UnityWebRequest")
        |> get(~p"/a/5/sr/#{slot.id}")
        |> json_response(200)
      end)
    end)
    |> Enum.map(fn task ->
      resp = Task.await(task)
      assert resp["subtitle_data"] == "Among Us ORIGINAL"
      assert length(resp["sponsorblock_segments"]) == 2
      assert length(resp["chapters"]) == 2
      assert resp["duration"] == slot.video_duration
    end)
  end

  test "metadata fails successfully on failure of external servers", %{ets_table: table} do
    slot = insert_slot()

    mock_global(fn
      %{method: :get, url: "sb.example.org/api/skipSegments?videoID=" <> rest} = env ->
        youtube_id = rest |> String.split("&") |> Enum.at(0)

        if youtube_id == slot.youtube_id do
          {:error, :timeout}
        else
          Logger.warning("mock: sb.example.org called with #{youtube_id}, not #{slot.youtube_id}")
          env
        end

      %{method: :get, url: "example.org/streams/" <> youtube_id} = env ->
        if youtube_id == slot.youtube_id do
          :timer.sleep(50)
          calls = :ets.update_counter(table, :ytdlp_cmd_3, 1, {:ytdlp_cmd_3, 0})

          unless calls > 1 do
            json(%{
              "subtitles" => [
                %{
                  "url" =>
                    "https://pipedproxy-cdg.kavin.rocks/api/timedtext?v=#{slot.youtube_id}&ei=k_TSZKi2ItWMobIPs7aF6AQ&caps=asr&opi=112496729&xoaf=5&lang=en&fmt=vtt&host=youtube.example.org",
                  "mimeType" => "text/vtt",
                  "name" => "English",
                  "code" => "en",
                  "autoGenerated" => true
                }
              ]
            })
          else
            %Tesla.Env{status: 500, body: "called mock too much (#{calls})"}
          end
        else
          env
        end

      %{
        method: :get,
        url: "https://youtube.example.org/api/timedtext?v=" <> rest
      } = env ->
        [youtube_id | _rest] = String.split(rest, "&")

        if youtube_id == slot.youtube_id do
          {:error, :timeout}
        else
          require Logger
          Logger.warning("invalid ytid #{youtube_id}")
          env
        end
    end)

    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        resp =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("user-agent", "UnityWebRequest")
          |> get(~p"/a/5/sl/#{slot.id}")

        assert resp.status == 302
      end)
    end)
    |> Enum.map(fn task ->
      resp = Task.await(task)
      assert resp["subtitle_data"] == nil
      assert resp["sponsorblock_segments"] == nil
    end)
  end

  test "links work under pressure and are only fetched once", %{ets_table: table} do
    slot = insert_slot()

    mock_global(fn
      %{method: :get, url: "example.org/streams/" <> youtube_id} = env ->
        if youtube_id == slot.youtube_id do
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
        else
          env
        end
    end)

    1..10
    |> Enum.map(fn _ ->
      Task.async(fn ->
        Phoenix.ConnTest.build_conn()
        |> get(~p"/api/v5/sr/#{slot.id}")
      end)
    end)
    |> Enum.map(fn task ->
      conn = Task.await(task)

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["awooga"]
    end)
  end

  test "it removes links from db that are already expired" do
    link =
      Mp4Link.insert(
        "abcdef",
        "https://freeeee--mp5.net",
        nil,
        %{}
      )

    # assert its still on db
    from_db = LinkRepo.one!(from s in Mp4Link, where: s.youtube_id == ^link.youtube_id, select: s)
    assert from_db.youtube_id == link.youtube_id
    assert NaiveDateTime.diff(from_db.inserted_at, NaiveDateTime.utc_now()) >= 0

    YtSearch.Mp4Link.Janitor.tick()

    from_db = LinkRepo.one(from s in Mp4Link, where: s.youtube_id == ^link.youtube_id, select: s)
    assert from_db.youtube_id == link.youtube_id

    # update then check
    link
    |> Ecto.Changeset.change(
      inserted_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-Mp4Link.ttl_seconds() - 1)
        |> NaiveDateTime.truncate(:second)
    )
    |> LinkRepo.update!()

    YtSearch.Mp4Link.Janitor.tick()
    from_db = LinkRepo.one(from s in Mp4Link, where: s.youtube_id == ^link.youtube_id, select: s)
    assert from_db == nil
  end

  test "it doesnt expose expired slots to main fetch function" do
    slot = insert_slot()

    slot
    |> Ecto.Changeset.change(
      expires_at:
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-10, :second)
        |> NaiveDateTime.truncate(:second)
    )
    |> SlotRepo.update!()

    assert Slot.fetch_by_id(slot.id) == nil

    # assert its still on db
    from_db = SlotRepo.one!(from s in Slot, where: s.id == ^slot.id, select: s)
    assert from_db.id == slot.id
  end

  test "it gives 200 on invalid youtube ids", %{conn: conn} do
    slot = insert_slot()

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
      |> get(~p"/a/5/sr/#{slot.id}")

    assert conn.status == 200
    assert response_content_type(conn, :mp4)
    assert get_resp_header(conn, "yts-failure-code") == ["E01"]
  end

  test "it refreshes the slot if its older than a minute", %{conn: conn} do
    slot = insert_slot()

    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams" <> _} ->
        Tesla.Mock.json(
          @run1
          |> Jason.decode!()
        )

      %{
        method: :get,
        url: "https://www.youtube.com/api/timedtext?v=" <> _
      } ->
        %Tesla.Env{status: 200, body: "Among Us"}

      %{method: :get, url: "sb.example.org/api/skipSegments?videoID=" <> _} ->
        json([
          %{
            "category" => "intro",
            "actionType" => "skip",
            "segment" => [
              0,
              1.925
            ],
            "UUID" => "24950dd1f8dc6bacac09a9bba19fee28064e2cf94101b4ec0e2003e2199ef7f57",
            "videoDuration" => 1626.561,
            "locked" => 0,
            "votes" => 0,
            "description" => ""
          }
        ])
    end)

    conn =
      conn
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/sr/#{slot.id}")

    assert conn.status == 200
    fetched_slot = Slot.fetch_by_id(slot.id)
    assert fetched_slot.inserted_at == slot.inserted_at

    slot =
      slot
      |> Ecto.Changeset.change(
        used_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-61, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> SlotRepo.update!()

    conn =
      build_conn()
      |> put_req_header("user-agent", "UnityWebRequest")
      |> get(~p"/a/5/sr/#{slot.id}")

    assert conn.status == 200
    fetched_slot = Slot.fetch_by_id(slot.id)
    assert fetched_slot.expires_at > slot.expires_at

    slot =
      slot
      |> Ecto.Changeset.change(
        used_at:
          NaiveDateTime.utc_now()
          |> NaiveDateTime.add(-61, :second)
          |> NaiveDateTime.truncate(:second)
      )
      |> SlotRepo.update!()

    conn =
      build_conn()
      |> get(~p"/a/5/qr/#{slot.id}")

    assert conn.status == 200
    fetched_slot = Slot.fetch_by_id(slot.id)
    assert fetched_slot.expires_at > slot.expires_at
    assert fetched_slot.used_at > slot.used_at
  end
end

defmodule YtSearchWeb.SlotConsistencyTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Slot
  alias YtSearch.Subtitle
  alias YtSearch.Mp4Link
  alias YtSearch.Test.Data
  alias YtSearch.Repo
  import Ecto.Query
  import Tesla.Mock
  require Logger

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

  @custom_expire (System.os_time(:second) + 3_600) |> to_string

  @run1 File.read!("test/support/piped_outputs/video_streams.json")
        |> String.replace("1691627905", @custom_expire)

  @expected_run1_url "https://rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com/videoplayback?expire=#{@custom_expire}&ei=Id3TZI2vOZ-lobIP_dmBiA4&ip=2804%3A14d%3A5492%3A8fe8%3A%3A1001&id=o-AHJX6AwsW-zQGeS4Eyu1Bdv-yjYJr1bEu-We0EmP4NDb&itag=22&source=youtube&requiressl=yes&mh=xI&mm=31%2C29&mn=sn-oxunxg8pjvn-gxjl%2Csn-gpv7knee&ms=au%2Crdu&mv=m&mvi=1&pl=52&initcwndbps=835000&spc=UWF9f3ylca2q7Fjk8ujpSFMzTN3TUXs&vprv=1&svpuc=1&mime=video%2Fmp4&cnr=14&ratebypass=yes&dur=666.435&lmt=1689626995182173&mt=1691606033&fvip=2&fexp=24007246%2C24362688&c=ANDROID&txp=5532434&sparams=expire%2Cei%2Cip%2Cid%2Citag%2Csource%2Crequiressl%2Cspc%2Cvprv%2Csvpuc%2Cmime%2Ccnr%2Cratebypass%2Cdur%2Clmt&sig=AOq0QJ8wRgIhAPypX1tk8JHpuo_QPe9KKVaiy-hbIBIXyq5qBBg963rzAiEAsnlp-AkDLpOmwhcgCQ1TKRrs-EtMl230VM_9SbNGg14%3D&lsparams=mh%2Cmm%2Cmn%2Cms%2Cmv%2Cmvi%2Cpl%2Cinitcwndbps&lsig=AG3C_xAwRAIgP3rzSh2MwDq2ZxW1Pcgfcf-pki_ahrDfZ1HFz4_5CpgCIHwqgkD-lup0L9EpoGyYEWjtM4XQEJjbppRu1aPaXV2A&cpn=iZTa_BP8GjO4tg7g&host=rr1---sn-oxunxg8pjvn-gxjl.googlevideo.com"

  defp stop_metadata_workers(_youtube_id) do
    DynamicSupervisor.which_children(YtSearch.MetadataSupervisor)
    |> Enum.each(fn {_id, child, _type, _modules} ->
      DynamicSupervisor.terminate_child(YtSearch.MetadataSupervisor, child)
    end)
  end

  defp unregister_metadata_workers(youtube_id) do
    with [{worker, :self}] <- Registry.lookup(YtSearch.MetadataWorkers, youtube_id) do
      :ok = GenServer.call(worker, :unregister)
      [] = Registry.lookup(YtSearch.MetadataWorkers, youtube_id)
    end

    IO.puts("want #{youtube_id}")

    with [{extractor, :self}] <-
           Registry.lookup(YtSearch.MetadataExtractors, {:mp4_link, youtube_id}) do
      IO.puts("unregister #{inspect(extractor)}")
      :ok = GenServer.call(extractor, :unregister)

      case Registry.lookup(YtSearch.MetadataExtractors, {:mp4_link, youtube_id}) do
        [{other, :self}] ->
          assert other != extractor

        [] ->
          :ok
      end
    end

    with [{extractor, :self}] <-
           Registry.lookup(YtSearch.MetadataExtractors, {:subtitles, youtube_id}) do
      IO.puts("unregister #{inspect(extractor)}")
      :ok = GenServer.call(extractor, :unregister)

      case Registry.lookup(YtSearch.MetadataExtractors, {:subtitles, youtube_id}) do
        [{other, :self}] ->
          assert other != extractor

        [] ->
          :ok
      end
    end
  end

  @tag :slow
  test "it gets the mp4 url given multiple deregisters back and forth" do
    slot = insert(:slot)

    Data.default_global_mock(fn
      %{method: :get, url: "example.org/streams/" <> wanted_youtube_id} = env ->
        :timer.sleep(:rand.uniform(100))

        if wanted_youtube_id == slot.youtube_id do
          Tesla.Mock.json(
            @run1
            |> Jason.decode!()
          )
        else
          # ignore requests not to the generated slot
          env
        end
    end)

    1..500
    |> Enum.map(fn _ ->
      Task.async(fn ->
        wanted_precondition = Enum.random([:unregister, :delete, :normal])

        conn =
          case wanted_precondition do
            :unregister ->
              unregister_metadata_workers(slot.youtube_id)
              IO.puts("call")

              conn =
                Phoenix.ConnTest.build_conn()
                |> get(~p"/a/2/sr/#{slot.id}")

              unregister_metadata_workers(slot.youtube_id)
              conn

            :delete ->
              if :rand.uniform(100) < 30 do
                from(s in Mp4Link,
                  where: s.youtube_id == ^slot.youtube_id
                )
                |> Repo.delete_all()

                unregister_metadata_workers(slot.youtube_id)
              else
                :timer.sleep(:rand.uniform(100))
              end

              IO.puts("call")

              conn =
                Phoenix.ConnTest.build_conn()
                |> get(~p"/a/2/sr/#{slot.id}")

              unregister_metadata_workers(slot.youtube_id)
              conn

            :normal ->
              :timer.sleep(:rand.uniform(200))

              unregister_metadata_workers(slot.youtube_id)
              IO.puts("call")
              :timer.sleep(:rand.uniform(100))

              conn =
                Phoenix.ConnTest.build_conn()
                |> get(~p"/a/2/sr/#{slot.id}")

              unregister_metadata_workers(slot.youtube_id)
              conn
          end

        conn
      end)
    end)
    |> Enum.map(fn task ->
      resp = Task.await(task)
      assert resp.status == 302

      assert get_resp_header(resp, "location") == [
               @expected_run1_url
             ]
    end)
  end

  @tag :skip
  test "it gets the subtitle given multiple deregisters back and forth" do
    slot = insert(:slot)

    mock_global(fn
      %{method: :get, url: "example.org/streams/" <> youtube_id} = env ->
        if youtube_id == slot.youtube_id do
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
          env
        end

      %{
        method: :get,
        url: "https://youtube.example.org/api/timedtext?v=" <> rest
      } = env ->
        [youtube_id | _rest] = String.split(rest, "&")

        if youtube_id == slot.youtube_id do
          %Tesla.Env{status: 200, body: "Among Us"}
        else
          Logger.warning("invalid ytid #{youtube_id}")
          env
        end
    end)

    1..500
    |> Enum.map(fn _ ->
      Task.async(fn ->
        # 70% of the requests are going to call upstream
        if :rand.uniform(100) < 70 do
          from(s in Subtitle,
            where: s.youtube_id == ^slot.youtube_id
          )
          |> Repo.delete_all()
        end

        # 50% of the requests are going to have new processes
        if :rand.uniform(100) < 50 do
          unregister_metadata_workers(slot.youtube_id)
        end

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
end

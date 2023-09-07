defmodule YtSearchWeb.SearchConsistencyTest do
  use YtSearchWeb.ConnCase, async: false
  alias YtSearch.Test.Data
  import Tesla.Mock

  setup do
    %{slots: 0..100 |> Enum.map(fn _ -> insert(:slot) end)}
  end

  1..100
  |> Enum.each(fn test_case ->
    @tag :slower
    @tag timeout: :infinity
    test "JUST MAKE A MORBILLION REQUESTS AND ASSERT THEY ALL WORK, edition #{test_case}", %{
      slots: slots
    } do
      Data.default_global_mock(fn
        %{method: :get, url: "example.org/search?q=" <> _suffix} ->
          json(%{
            "items" =>
              slots
              |> Enum.shuffle()
              |> Enum.slice(0..20)
              |> Enum.map(fn slot ->
                # hydrate it
                %{
                  "url" => "/watch?v=#{slot.youtube_id}",
                  "type" => "stream",
                  "title" => "AAAA #{slot.youtube_id}",
                  "thumbnail" =>
                    "https://pipedproxy-cdg.kavin.rocks/vi/FUCK/hqdefault.jpg?sqp=-DKLGJDFSJGALSKDJFKL==&rs=AAAAAA&host=i.ytimg.com",
                  "uploaderName" => "BALLS",
                  "uploaderUrl" => "/channel/FUCK",
                  "uploaderAvatar" => "SHIT",
                  "shortDescription" => "AAHHH",
                  "duration" => 666,
                  "views" => 666,
                  "uploaded" => DateTime.utc_now() |> DateTime.to_unix(),
                  "uploaderVerified" => false,
                  "isShort" => false
                }
              end)
          })
      end)

      1..50
      |> Enum.chunk_every(50)
      |> Enum.map(fn chunk ->
        IO.puts("chunk: #{inspect(chunk)}")

        chunk
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Phoenix.ConnTest.build_conn()
            |> put_req_header("user-agent", "UnityWebRequest")
            |> get(~p"/api/v3/search?q=dslkgjaslfdkj")
          end)
        end)
        |> Enum.map(fn task ->
          conn = Task.await(task)
          json_response(conn, 200)
        end)
      end)
    end
  end)
end

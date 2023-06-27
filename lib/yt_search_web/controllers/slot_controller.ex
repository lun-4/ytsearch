defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  alias YtSearch.Slot
  alias YtSearch.Mp4Link

  def fetch_video(conn, %{"slot_id" => slot_id_query}) do
    {slot_id, _} = slot_id_query |> Integer.parse()

    case Slot.fetch_by_id(slot_id) do
      nil ->
        conn
        |> put_status(404)

      slot ->
        agent =
          case get_req_header(conn, "user-agent") do
            [] -> ""
            v -> Enum.at(v, 0)
          end

        youtube_url = "https://youtube.com/watch?v=#{slot.youtube_id}"

        if String.contains?(agent, "stagefright") or String.contains?(agent, "AVProMobileVideo") do
          mp4_url =
            case Mp4Link.fetch_by_id(slot.youtube_id) do
              nil ->
                fetch_mp4_link(slot.youtube_id, youtube_url)

              data ->
                data.mp4_link
            end

          conn
          |> redirect(external: mp4_url)
        else
          conn
          |> redirect(external: youtube_url)
        end
    end
  end

  defp fetch_mp4_link(youtube_id, youtube_url) do
    Mutex.under(Mp4LinkMutex, youtube_id, fn ->
      IO.puts("calling mp4")

      # refetch to prevent double fetch
      case Mp4Link.fetch_by_id(youtube_id) do
        nil ->
          # get mp4 from ytdlp
          IO.puts("calling mp4 for real")

          {output, exit_status} =
            System.cmd("yt-dlp", [
              "--no-check-certificate",
              "--no-cache-dir",
              "--rm-cache-dir",
              "-f",
              "mp4[height<=?1080][height>=?64][width>=?64]/best[height<=?1080][height>=?64][width>=?64]",
              "--get-url",
              youtube_url
            ])

          new_mp4_link = String.trim(output)
          Mp4Link.insert(youtube_id, new_mp4_link)
          new_mp4_link

        link ->
          link.mp4_link
      end
    end)
  end
end

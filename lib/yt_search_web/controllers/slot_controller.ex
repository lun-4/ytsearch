defmodule YtSearchWeb.SlotController do
  use YtSearchWeb, :controller
  alias YtSearch.Slot

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
          # get mp4 from ytdlp
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

          mp4_url = String.trim(output)

          conn
          |> redirect(external: mp4_url)
        else
          conn
          |> redirect(external: youtube_url)
        end
    end
  end
end

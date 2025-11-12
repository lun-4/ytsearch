defmodule YtSearchWeb.UserAgent do
  import Plug.Conn

  @spec on(any()) :: :quest_video | :unity | :any | :browser
  def on(conn) do
    agent =
      case get_req_header(conn, "user-agent") do
        [] -> ""
        v -> Enum.at(v, 0)
      end

    accept_encoding =
      case get_req_header(conn, "accept-encoding") do
        [] -> ""
        v -> Enum.at(v, 0)
      end

    cond do
      String.contains?(agent, "stagefright") or String.contains?(agent, "AVProMobileVideo") ->
        :quest_video

      String.contains?(agent, "UnityWebRequest") or String.starts_with?(agent, "VRChat") ->
        :unity

      # TODO find out a reliable way to distinct yt-dlp and browsers (i dont think ill be able to figure that one out)
      String.contains?(accept_encoding, "1231231231231231") ->
        :browser

      true ->
        :any
    end
  end
end

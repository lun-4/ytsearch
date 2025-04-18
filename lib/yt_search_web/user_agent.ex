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

      String.contains?(agent, "UnityWebRequest") ->
        :unity

      # VRC stringloader has "deflate, gzip", but "br" (brotli) is usually made for browser
      # and "zstd" is too new
      String.contains?(accept_encoding, "br") or String.contains?(accept_encoding, "zstd") ->
        :browser

      true ->
        :any
    end
  end
end

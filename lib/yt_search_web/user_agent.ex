defmodule YtSearchWeb.UserAgent do
  import Plug.Conn

  def is_quest_two(conn) do
    agent =
      case get_req_header(conn, "user-agent") do
        [] -> ""
        v -> Enum.at(v, 0)
      end

    String.contains?(agent, "stagefright") or String.contains?(agent, "AVProMobileVideo")
  end
end

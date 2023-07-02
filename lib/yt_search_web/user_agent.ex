defmodule YtSearchWeb.UserAgent do
  import Plug.Conn

  @spec for(any()) :: :quest | :unity | :any
  def for(conn) do
    agent =
      case get_req_header(conn, "user-agent") do
        [] -> ""
        v -> Enum.at(v, 0)
      end

    cond do
      String.contains?(agent, "stagefright") or String.contains?(agent, "AVProMobileVideo") ->
        :quest

      String.contains?(agent, "UnityWebRequest") ->
        :unity

      true ->
        :any
    end
  end
end

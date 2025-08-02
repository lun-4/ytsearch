defmodule YtSearchWeb.CounterController do
  use YtSearchWeb, :controller
  alias YtSearch.CounterServer

  def increment(conn, %{"delta" => delta_str} = params) do
    case Integer.parse(delta_str) do
      {num, ""} ->
        if num >= 0 and num <= 1000 do
          do_increment(conn, params)
        else
          conn
          |> put_status(400)
          |> json(%{error: true, message: "invalid delta range (0-1000)"})
        end

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "invalid delta (must be int)"})
    end
  end

  defp do_increment(conn, %{"delta" => delta_str}) do
    {delta, ""} = Integer.parse(delta_str)
    CounterServer.increment(delta)

    current_value =
      CounterServer.get_value()
      |> Map.put(:added, delta)

    conn
    |> json(current_value)
  end
end

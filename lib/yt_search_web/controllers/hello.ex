defmodule YtSearchWeb.HelloController do
  use YtSearchWeb, :controller

  def hello(conn, _params) do
    conn
    |> json(%{online: true})
  end
end

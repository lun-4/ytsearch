defmodule YtSearch.ThumbnailHttpClient do
  use Tesla

  plug(Tesla.Middleware.Opts, build_opts())

  defp build_opts do
    # this is done just so that we can inject socks5 *only* to thumbnailer
    # (doing it at global level wouldn't work, you may run piped on localhost and doing localhost via socks5
    # just sounds and likely is just Wrong)
    config = Application.get_env(:yt_search, __MODULE__, [])
    host = Keyword.get(config, :socks5_host)
    port = Keyword.get(config, :socks5_port)

    case {host, port} do
      {host, port} when is_binary(host) and is_binary(port) ->
        port_int = String.to_integer(port)
        [proxy: {:socks5, String.to_charlist(host), port_int}]

      _ ->
        []
    end
  end
end

defmodule YtSearchWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :yt_search

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_yt_search_key",
    signing_salt: "i+PwKqz0",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :yt_search,
    gzip: false,
    only: YtSearchWeb.static_paths()
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :yt_search)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)

  defmodule PipelineInstrumenter do
    use Prometheus.PlugPipelineInstrumenter
  end

  defmodule MetricsExporter do
    use Prometheus.PlugExporter
  end

  defmodule JSONRequestIDSetter do
    import Plug.Conn
    @behaviour Plug

    def init(options) do
      options
    end

    defp do_call(conn) do
      content_types = get_resp_header(conn, "content-type")
      [x_request_id] = get_resp_header(conn, "x-request-id")
      server_time = System.system_time(:millisecond) / 1000

      # splice the keys into the already-encoded body instead of a full
      # decode+re-encode round-trip. only object bodies get the keys,
      # matching the old is_map(body) behavior
      with [type] <- content_types,
           "application/json" <> _whatever <- type,
           "{" <> rest <- conn.resp_body |> IO.iodata_to_binary() |> String.trim_leading() do
        # __time is used for counter syncing
        injected =
          ~s({"__x_request_id":) <>
            Jason.encode!(x_request_id) <>
            ~s(,"__time":) <> Float.to_string(server_time)

        # decide the comma by the trimmed remainder: an empty object ("{}" with
        # any interior whitespace) starts with "}" and must not get a trailing comma
        new_body =
          case String.trim_leading(rest) do
            "}" <> _ = trimmed -> injected <> trimmed
            trimmed -> injected <> "," <> trimmed
          end

        conn
        |> resp(conn.status, new_body)
      else
        _value ->
          conn
      end
    end

    def call(conn, _opts) do
      register_before_send(conn, &do_call/1)
    end
  end

  plug(PipelineInstrumenter)
  plug(MetricsExporter)
  plug(JSONRequestIDSetter)

  plug(YtSearchWeb.Router)
end

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

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :yt_search,
    gzip: false,
    only: YtSearchWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :yt_search
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  defmodule Instrumenter do
    use Prometheus.PhoenixInstrumenter
  end

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
      values = get_resp_header(conn, "content-type")
      [x_request_id] = get_resp_header(conn, "x-request-id")

      # TODO convert this to with
      case values do
        [type] ->
          case type do
            "application/json" <> _whatever ->
              new_body =
                case conn.resp_body
                     |> Jason.decode() do
                  {:ok, body} ->
                    cond do
                      is_map(body) ->
                        body
                        |> Map.put("__x_request_id", x_request_id)

                      true ->
                        body
                    end
                    |> Jason.encode!()

                  _ ->
                    conn.resp_body
                end

              conn
              |> resp(conn.status, new_body)

            _ ->
              conn
          end

        _ ->
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

  plug YtSearchWeb.Router
end

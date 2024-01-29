defmodule YtSearchWeb.AngelOfDeathController do
  use YtSearchWeb, :controller

  def report_error(conn, params) do
    __MODULE__.ErrorCounter.increment(params["error_id"])

    conn
    |> put_status(200)
    |> json(nil)
  end

  @retry_error_reply Path.join(:code.priv_dir(:yt_search), "static/retry.png")
  def report_video_retry_error(conn, params) do
    __MODULE__.ErrorCounter.increment("retry")

    conn
    |> put_resp_header("content-type", "image/png")
    |> resp(200, File.read!(@retry_error_reply))
  end

  defmodule ErrorCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_world_error,
        help: "errors reported by world",
        labels: [:error_id]
      )
    end

    def increment(error_id) do
      Counter.inc(
        name: :yts_world_error,
        labels: [error_id]
      )
    end
  end
end

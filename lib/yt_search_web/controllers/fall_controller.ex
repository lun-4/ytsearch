defmodule YtSearchWeb.FallController do
  use YtSearchWeb, :controller
  alias YtSearch.Counter

  def increment(conn, %{"number" => number_str}) do
    case YtSearchWeb.UserAgent.on(conn) do
      :unity ->
        case Integer.parse(number_str) do
          # must be 1 fall per request lol
          {num, ""} when num == 1 ->
            __MODULE__.FallCounter.increment(num)
            counter = Counter.increment(num, :falls)
            __MODULE__.FallCounter.set_db(counter.value)
            conn |> json(%{falls: counter.value, added: num})

          _ ->
            conn
            |> put_status(400)
            |> json(%{error: true, message: "invalid fall amount"})
        end

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "only unity should request this route"})
    end
  end

  defmodule FallCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_falls,
        help: "falls over time"
      )

      Gauge.declare(
        name: :yts_falls_db,
        help: "total falls (db)"
      )
    end

    def increment(amount), do: Counter.inc([name: :yts_falls], amount)
    def set_db(value), do: Gauge.set([name: :yts_falls_db], value)
  end
end

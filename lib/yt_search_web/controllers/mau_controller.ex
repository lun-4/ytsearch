defmodule YtSearchWeb.MAUController do
  use YtSearchWeb, :controller
  alias YtSearch.Counter

  def increment(conn, %{"number" => number_str}) do
    case YtSearchWeb.UserAgent.on(conn) do
      :unity ->
        case Integer.parse(number_str) do
          # must be 1 mau per request lol
          {num, ""} when num == 1 ->
            __MODULE__.MAUCounter.increment(num)
            counter = Counter.increment(num, :mau_counter)
            __MODULE__.MAUCounter.set_db(counter.value)
            conn |> json(%{m: counter.value, added: num})

          _ ->
            conn
            |> put_status(400)
            |> json(%{error: true, message: "invalid mau amount"})
        end

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "only unity should request this route"})
    end
  end

  defmodule MAUCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_mau_counter,
        help: "mau counter (incremented on request)"
      )

      Gauge.declare(
        name: :yts_mau_counter_db,
        help: "mau counter total (from db)"
      )
    end

    def increment(amount), do: Counter.inc([name: :yts_mau_counter], amount)
    def set_db(value), do: Gauge.set([name: :yts_mau_counter_db], value)
  end
end

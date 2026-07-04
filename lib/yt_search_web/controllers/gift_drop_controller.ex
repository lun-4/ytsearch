defmodule YtSearchWeb.GiftDropController do
  use YtSearchWeb, :controller
  alias YtSearch.Counter

  def increment(conn, %{"number" => number_str}) do
    case YtSearchWeb.UserAgent.on(conn) do
      :unity ->
        case Integer.parse(number_str) do
          {num, ""} when num >= 1 and num <= 100 ->
            __MODULE__.GiftCounter.increment(num)
            counter = Counter.increment(num, :gift_drops)
            __MODULE__.GiftCounter.set_db(counter.value)
            conn |> json(%{gifts: counter.value, added: num})

          _ ->
            conn
            |> put_status(400)
            |> json(%{error: true, message: "invalid gift amount (1-100)"})
        end

      _ ->
        conn
        |> put_status(400)
        |> json(%{error: true, message: "only unity should request this route"})
    end
  end

  defmodule GiftCounter do
    use Prometheus.Metric

    def setup() do
      Counter.declare(
        name: :yts_vrcplus_gift_drops,
        help: "vrc+ gift drops reported by world instances (incremented on request)"
      )

      Gauge.declare(
        name: :yts_vrcplus_gift_drops_db,
        help: "vrc+ gift drops total (from db)"
      )
    end

    def increment(amount), do: Counter.inc([name: :yts_vrcplus_gift_drops], amount)
    def set_db(value), do: Gauge.set([name: :yts_vrcplus_gift_drops_db], value)
  end
end

defmodule YtSearch.Repo do
  use Ecto.Repo,
    otp_app: :yt_search,
    adapter: Ecto.Adapters.SQLite3,
    pool_size: 1

  defmodule Instrumenter, do: use(Prometheus.EctoInstrumenter)
end

defmodule YtSearch.Repo do
  use Ecto.Repo,
    otp_app: :yt_search,
    adapter: Ecto.Adapters.SQLite3
end

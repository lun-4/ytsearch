import Config

# Configure your database

repos = [
  YtSearch.Repo,
  YtSearch.Repo.Replica1,
  YtSearch.Repo.Replica2,
  YtSearch.Repo.Replica3,
  YtSearch.Repo.Replica4,
  YtSearch.Repo.Replica5,
  YtSearch.Repo.Replica6,
  YtSearch.Repo.Replica7,
  YtSearch.Repo.Replica8,
  YtSearch.Repo.ThumbnailReplica,
  YtSearch.Repo.LinkReplica,
  YtSearch.Repo.SubtitleReplica,
  YtSearch.Repo.ChapterReplica
]

for repo <- repos do
  config :yt_search, repo,
    database: Path.expand("../yt_search_dev.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

for repo <- [
      YtSearch.Data.SlotRepo,
      YtSearch.Data.SlotRepo.Replica1,
      YtSearch.Data.SlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_dev_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

for repo <- [
      YtSearch.Data.ChannelSlotRepo,
      YtSearch.Data.ChannelSlotRepo.Replica1,
      YtSearch.Data.ChannelSlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_dev_channel_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

for repo <- [
      YtSearch.Data.PlaylistSlotRepo,
      YtSearch.Data.PlaylistSlotRepo.Replica1,
      YtSearch.Data.PlaylistSlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_dev_playlist_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

for repo <- [
      YtSearch.Data.SearchSlotRepo,
      YtSearch.Data.SearchSlotRepo.Replica1,
      YtSearch.Data.SearchSlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_dev_search_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

for repo <- [
      YtSearch.Data.ThumbnailRepo,
      YtSearch.Data.ThumbnailRepo.Replica1,
      YtSearch.Data.ThumbnailRepo.Replica2,
      YtSearch.Data.ThumbnailRepo.JanitorReplica
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_dev_thumbnails.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

for repo <- [
      YtSearch.Data.ChapterRepo,
      YtSearch.Data.ChapterRepo.Replica1,
      YtSearch.Data.ChapterRepo.Replica2,
      YtSearch.Data.ChapterRepo.JanitorReplica
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_dev_chapters.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    stacktrace: true,
    show_sensitive_data_on_connection_error: true
end

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :yt_search, YtSearchWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "TaKSaRg6sxJHM3t1+rgLCtrkBblqqRldvRSWPa537/zFmr3Rx/VW9qRpyTNPCUZJ",
  watchers: []

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Enable dev routes for dashboard and mailbox
config :yt_search, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

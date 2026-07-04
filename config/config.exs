# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :yt_search,
  ecto_repos: [
    YtSearch.Data.SlotRepo,
    YtSearch.Data.ChannelSlotRepo,
    YtSearch.Data.PlaylistSlotRepo,
    YtSearch.Data.SearchSlotRepo,
    YtSearch.Data.ThumbnailRepo,
    YtSearch.Data.ChapterRepo,
    YtSearch.Data.SponsorblockRepo,
    YtSearch.Data.SubtitleRepo,
    YtSearch.Data.LinkRepo,
    YtSearch.Data.AudioConfigRepo,
    YtSearch.Data.CounterRepo
  ] ++
    if(System.get_env("EXTERNAL_TRENDING_NODE") in [nil, ""],
      do: [YtSearch.Data.TrendingRepo],
      else: []
    )

# Configures the endpoint
config :yt_search, YtSearchWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [json: YtSearchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: YtSearch.PubSub,
  live_view: [signing_salt: "7p7hMPr9"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :yt_search, YtSearch.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :yt_search, YtSearch.Youtube,
  piped_url: "localhost:8080",
  sponsorblock_url: "localhost:8081"

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

config :yt_search, YtSearch.Ratelimit, ytdlp_search: {1, 1 * 1000}

repos = [
  YtSearch.Data.SlotRepo,
  YtSearch.Data.SlotRepo.Replica1,
  YtSearch.Data.SlotRepo.Replica2,
  YtSearch.Data.SlotRepo.Replica3,
  YtSearch.Data.SlotRepo.Replica4,
  YtSearch.Data.SlotRepo.Replica5,
  YtSearch.Data.SlotRepo.Replica6,
  YtSearch.Data.SlotRepo.Replica7,
  YtSearch.Data.SlotRepo.Replica8,
  YtSearch.Data.SlotRepo.Replica9,
  YtSearch.Data.SlotRepo.Replica10,
  YtSearch.Data.ChannelSlotRepo,
  YtSearch.Data.ChannelSlotRepo.Replica1,
  YtSearch.Data.ChannelSlotRepo.Replica2,
  YtSearch.Data.ChannelSlotRepo.Replica3,
  YtSearch.Data.ChannelSlotRepo.Replica4,
  YtSearch.Data.ChannelSlotRepo.Replica5,
  YtSearch.Data.ChannelSlotRepo.Replica6,
  YtSearch.Data.ChannelSlotRepo.Replica7,
  YtSearch.Data.ChannelSlotRepo.Replica8,
  YtSearch.Data.ChannelSlotRepo.Replica9,
  YtSearch.Data.ChannelSlotRepo.Replica10,
  YtSearch.Data.PlaylistSlotRepo,
  YtSearch.Data.PlaylistSlotRepo.Replica1,
  YtSearch.Data.PlaylistSlotRepo.Replica2,
  YtSearch.Data.PlaylistSlotRepo.Replica3,
  YtSearch.Data.PlaylistSlotRepo.Replica4,
  YtSearch.Data.PlaylistSlotRepo.Replica5,
  YtSearch.Data.PlaylistSlotRepo.Replica6,
  YtSearch.Data.PlaylistSlotRepo.Replica7,
  YtSearch.Data.PlaylistSlotRepo.Replica8,
  YtSearch.Data.PlaylistSlotRepo.Replica9,
  YtSearch.Data.PlaylistSlotRepo.Replica10,
  YtSearch.Data.SearchSlotRepo,
  YtSearch.Data.SearchSlotRepo.Replica1,
  YtSearch.Data.SearchSlotRepo.Replica2,
  YtSearch.Data.SearchSlotRepo.Replica3,
  YtSearch.Data.SearchSlotRepo.Replica4,
  YtSearch.Data.SearchSlotRepo.Replica5,
  YtSearch.Data.SearchSlotRepo.Replica6,
  YtSearch.Data.SearchSlotRepo.Replica7,
  YtSearch.Data.SearchSlotRepo.Replica8,
  YtSearch.Data.SearchSlotRepo.Replica9,
  YtSearch.Data.SearchSlotRepo.Replica10,
  YtSearch.Data.ThumbnailRepo,
  YtSearch.Data.ThumbnailRepo.Replica1,
  YtSearch.Data.ThumbnailRepo.Replica2,
  YtSearch.Data.ThumbnailRepo.Replica3,
  YtSearch.Data.ThumbnailRepo.Replica4,
  YtSearch.Data.ThumbnailRepo.Replica5,
  YtSearch.Data.ThumbnailRepo.JanitorReplica,
  YtSearch.Data.ChapterRepo,
  YtSearch.Data.ChapterRepo.Replica1,
  YtSearch.Data.ChapterRepo.Replica2,
  YtSearch.Data.ChapterRepo.Replica3,
  YtSearch.Data.ChapterRepo.Replica4,
  YtSearch.Data.ChapterRepo.Replica5,
  YtSearch.Data.ChapterRepo.JanitorReplica,
  YtSearch.Data.SponsorblockRepo,
  YtSearch.Data.SponsorblockRepo.Replica1,
  YtSearch.Data.SponsorblockRepo.Replica2,
  YtSearch.Data.SponsorblockRepo.Replica3,
  YtSearch.Data.SponsorblockRepo.Replica4,
  YtSearch.Data.SponsorblockRepo.Replica5,
  YtSearch.Data.SponsorblockRepo.JanitorReplica,
  YtSearch.Data.SubtitleRepo,
  YtSearch.Data.SubtitleRepo.Replica1,
  YtSearch.Data.SubtitleRepo.Replica2,
  YtSearch.Data.SubtitleRepo.Replica3,
  YtSearch.Data.SubtitleRepo.Replica4,
  YtSearch.Data.SubtitleRepo.Replica5,
  YtSearch.Data.SubtitleRepo.JanitorReplica,
  YtSearch.Data.LinkRepo,
  YtSearch.Data.LinkRepo.Replica1,
  YtSearch.Data.LinkRepo.Replica2,
  YtSearch.Data.LinkRepo.Replica3,
  YtSearch.Data.LinkRepo.Replica4,
  YtSearch.Data.LinkRepo.Replica5,
  YtSearch.Data.LinkRepo.JanitorReplica,
  YtSearch.Data.AudioConfigRepo,
  YtSearch.Data.AudioConfigRepo.Replica1,
  YtSearch.Data.AudioConfigRepo.Replica2,
  YtSearch.Data.AudioConfigRepo.Replica3,
  YtSearch.Data.AudioConfigRepo.Replica4,
  YtSearch.Data.AudioConfigRepo.Replica5,
  YtSearch.Data.AudioConfigRepo.JanitorReplica,
  YtSearch.Data.CounterRepo,
  YtSearch.Data.CounterRepo.Replica1,
  YtSearch.Data.CounterRepo.Replica2,
  YtSearch.Data.CounterRepo.Replica3,
  YtSearch.Data.CounterRepo.Replica4
] ++
  if(System.get_env("EXTERNAL_TRENDING_NODE") in [nil, ""],
    do: [
      YtSearch.Data.TrendingRepo,
      YtSearch.Data.TrendingRepo.Replica1,
      YtSearch.Data.TrendingRepo.Replica2
    ],
    else: []
  )

for repo <- repos do
  config :yt_search, repo,
    cache_size: -8_000,
    pool_size: 1,
    journal_mode: :wal,
    synchronous: :normal,
    foreign_keys: :on,
    temp_store: :memory,
    # busy_timeout is applied via custom_pragmas so it's set BEFORE the
    # journal_mode pragma during connect, avoiding "database is locked"
    # races on fresh databases; the top-level key is ALSO needed because
    # exqlite unconditionally re-applies busy_timeout (default 2000) late
    # in the connect sequence, which would clobber the custom_pragmas value
    busy_timeout: 5_000,
    custom_pragmas: [busy_timeout: 5000, mmap_size: 268_435_456],
    auto_vacuum: :incremental,
    telemetry_prefix: [:yt_search, :repo],
    telemetry_event: [YtSearch.Repo.Instrumenter],
    queue_target: 500,
    queue_interval: 2000
end

config :prometheus, YtSearch.Repo.Instrumenter,
  stages: [:queue, :query, :decode],
  counter: true,
  labels: [:result, :query, :repo],
  query_duration_buckets: [
    10,
    100,
    1_000,
    10_000,
    100_000,
    300_000,
    500_000,
    750_000,
    1_000_000,
    1_500_000,
    2_000_000,
    3_000_000
  ],
  registry: :default,
  duration_unit: :milliseconds

config :tesla, adapter: Tesla.Adapter.Hackney

config :yt_search, YtSearch.ThumbnailAtlas, montage_command: "montage"

config :phoenix_ecto,
  exclude_ecto_exceptions_from_plug: [Ecto.StaleEntryError]

config :yt_search, YtSearch.Constants,
  pages_from_search: 1,
  results_from_search: 20,
  pages_from_channels: 1,
  results_from_channels: 30,
  pages_from_playlists: 1,
  results_from_playlists: 30,
  pages_from_trending: 1,
  results_from_trending: 30,
  minimum_time_between_refreshes: 60,
  enable_periodic_tasks: true,
  enable_periodic_janitors: true,
  redirect_to_googlevideo?: true,
  extract_cta?: true,
  thumbnails_in_search_page: 32

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

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
    YtSearch.Data.LinkRepo
  ]

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
  YtSearch.Data.ChannelSlotRepo,
  YtSearch.Data.ChannelSlotRepo.Replica1,
  YtSearch.Data.ChannelSlotRepo.Replica2,
  YtSearch.Data.PlaylistSlotRepo,
  YtSearch.Data.PlaylistSlotRepo.Replica1,
  YtSearch.Data.PlaylistSlotRepo.Replica2,
  YtSearch.Data.SearchSlotRepo,
  YtSearch.Data.SearchSlotRepo.Replica1,
  YtSearch.Data.SearchSlotRepo.Replica2,
  YtSearch.Data.ThumbnailRepo,
  YtSearch.Data.ThumbnailRepo.Replica1,
  YtSearch.Data.ThumbnailRepo.Replica2,
  YtSearch.Data.ThumbnailRepo.JanitorReplica,
  YtSearch.Data.ChapterRepo,
  YtSearch.Data.ChapterRepo.Replica1,
  YtSearch.Data.ChapterRepo.Replica2,
  YtSearch.Data.ChapterRepo.JanitorReplica,
  YtSearch.Data.SponsorblockRepo,
  YtSearch.Data.SponsorblockRepo.Replica1,
  YtSearch.Data.SponsorblockRepo.Replica2,
  YtSearch.Data.SponsorblockRepo.JanitorReplica,
  YtSearch.Data.SubtitleRepo,
  YtSearch.Data.SubtitleRepo.Replica1,
  YtSearch.Data.SubtitleRepo.Replica2,
  YtSearch.Data.SubtitleRepo.JanitorReplica,
  YtSearch.Data.LinkRepo,
  YtSearch.Data.LinkRepo.Replica1,
  YtSearch.Data.LinkRepo.Replica2,
  YtSearch.Data.LinkRepo.JanitorReplica
]

for repo <- repos do
  config :yt_search, repo,
    cache_size: -8_000,
    auto_vacuum: :incremental,
    telemetry_prefix: [:yt_search, :repo],
    telemetry_event: [YtSearch.Repo.Instrumenter]
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
  results_from_search: 20,
  minimum_time_between_refreshes: 60,
  enable_periodic_tasks: true,
  enable_periodic_janitors: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

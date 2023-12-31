# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :yt_search,
  ecto_repos: [
    YtSearch.Repo,
    YtSearch.Data.SlotRepo,
    YtSearch.Data.ChannelSlotRepo,
    YtSearch.Data.PlaylistSlotRepo,
    YtSearch.Data.SearchSlotRepo
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
  YtSearch.Repo.ChapterReplica,
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
  YtSearch.Data.SearchSlotRepo.Replica2
]

for repo <- repos do
  config :yt_search, repo,
    cache_size: -16_000,
    auto_vacuum: :incremental,
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

import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

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
    database: Path.expand("../yt_search_test.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    queue_target: 10000,
    queue_timeout: 10000,
    pool: Ecto.Adapters.SQL.Sandbox
end

for repo <- [
      YtSearch.Data.SlotRepo,
      YtSearch.Data.SlotRepo.Replica1,
      YtSearch.Data.SlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_test_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    queue_target: 10000,
    queue_timeout: 10000,
    pool: Ecto.Adapters.SQL.Sandbox
end

for repo <- [
      YtSearch.Data.ChannelSlotRepo,
      YtSearch.Data.ChannelSlotRepo.Replica1,
      YtSearch.Data.ChannelSlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_test_channel_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    queue_target: 10000,
    queue_timeout: 10000,
    pool: Ecto.Adapters.SQL.Sandbox
end

for repo <- [
      YtSearch.Data.PlaylistSlotRepo,
      YtSearch.Data.PlaylistSlotRepo.Replica1,
      YtSearch.Data.PlaylistSlotRepo.Replica2
    ] do
  config :yt_search, repo,
    database: Path.expand("../db/yt_search_test_playlist_slots.db", Path.dirname(__ENV__.file)),
    pool_size: 1,
    queue_target: 10000,
    queue_timeout: 10000,
    pool: Ecto.Adapters.SQL.Sandbox
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :yt_search, YtSearchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YU4DQYJscYG4dtY0S1UEhBfLFqlf2savQ7OEIcKmHjoHMnS0TZ+n3Bl1OquzUFCj",
  server: false

# In test we don't send emails.
config :yt_search, YtSearch.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :tesla, adapter: Tesla.Mock

config :yt_search, YtSearch.Youtube, piped_url: "example.org", sponsorblock_url: "sb.example.org"

config :yt_search, YtSearch.Ratelimit, ytdlp_search: {1_000_000, 1}

import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.

[
  {[
     YtSearch.Data.SlotRepo,
     YtSearch.Data.SlotRepo.Replica1,
     YtSearch.Data.SlotRepo.Replica2
   ], "slots"},
  {[
     YtSearch.Data.ChannelSlotRepo,
     YtSearch.Data.ChannelSlotRepo.Replica1,
     YtSearch.Data.ChannelSlotRepo.Replica2
   ], "channel_slots"},
  {[
     YtSearch.Data.PlaylistSlotRepo,
     YtSearch.Data.PlaylistSlotRepo.Replica1,
     YtSearch.Data.PlaylistSlotRepo.Replica2
   ], "playlist_slots"},
  {[
     YtSearch.Data.SearchSlotRepo,
     YtSearch.Data.SearchSlotRepo.Replica1,
     YtSearch.Data.SearchSlotRepo.Replica2
   ], "search_slots"},
  {[
     YtSearch.Data.ThumbnailRepo,
     YtSearch.Data.ThumbnailRepo.Replica1,
     YtSearch.Data.ThumbnailRepo.Replica2,
     YtSearch.Data.ThumbnailRepo.JanitorReplica
   ], "thumbnails"},
  {[
     YtSearch.Data.ChapterRepo,
     YtSearch.Data.ChapterRepo.Replica1,
     YtSearch.Data.ChapterRepo.Replica2,
     YtSearch.Data.ChapterRepo.Replica3,
     YtSearch.Data.ChapterRepo.Replica4,
     YtSearch.Data.ChapterRepo.JanitorReplica
   ], "chapters"},
  {
    [
      YtSearch.Data.SponsorblockRepo,
      YtSearch.Data.SponsorblockRepo.Replica1,
      YtSearch.Data.SponsorblockRepo.Replica2,
      YtSearch.Data.SponsorblockRepo.Replica3,
      YtSearch.Data.SponsorblockRepo.Replica4,
      YtSearch.Data.SponsorblockRepo.JanitorReplica
    ],
    "sponsorblock"
  },
  {
    [
      YtSearch.Data.SubtitleRepo,
      YtSearch.Data.SubtitleRepo.Replica1,
      YtSearch.Data.SubtitleRepo.Replica2,
      YtSearch.Data.SubtitleRepo.JanitorReplica
    ],
    "subtitles"
  },
  {
    [
      YtSearch.Data.LinkRepo,
      YtSearch.Data.LinkRepo.Replica1,
      YtSearch.Data.LinkRepo.Replica2,
      YtSearch.Data.LinkRepo.JanitorReplica
    ],
    "links"
  }
]
|> Enum.each(fn {repos, name} ->
  for repo <- repos do
    config :yt_search, repo,
      database: Path.expand("../db/yt_search_test_#{name}.db", Path.dirname(__ENV__.file)),
      pool_size: 1,
      queue_target: 10000,
      queue_timeout: 10000,
      pool: Ecto.Adapters.SQL.Sandbox
  end
end)

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

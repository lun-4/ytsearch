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
     YtSearch.Data.SlotRepo.Replica2,
     YtSearch.Data.SlotRepo.Replica3,
     YtSearch.Data.SlotRepo.Replica4,
     YtSearch.Data.SlotRepo.Replica5,
     YtSearch.Data.SlotRepo.Replica6,
     YtSearch.Data.SlotRepo.Replica7,
     YtSearch.Data.SlotRepo.Replica8,
     YtSearch.Data.SlotRepo.Replica9,
     YtSearch.Data.SlotRepo.Replica10
   ], "slots"},
  {[
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
     YtSearch.Data.ChannelSlotRepo.Replica10
   ], "channel_slots"},
  {[
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
     YtSearch.Data.PlaylistSlotRepo.Replica10
   ], "playlist_slots"},
  {[
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
     YtSearch.Data.SearchSlotRepo.Replica10
   ], "search_slots"},
  {[
     YtSearch.Data.ThumbnailRepo,
     YtSearch.Data.ThumbnailRepo.Replica1,
     YtSearch.Data.ThumbnailRepo.Replica2,
     YtSearch.Data.ThumbnailRepo.Replica3,
     YtSearch.Data.ThumbnailRepo.Replica4,
     YtSearch.Data.ThumbnailRepo.Replica5,
     YtSearch.Data.ThumbnailRepo.JanitorReplica
   ], "thumbnails"},
  {[
     YtSearch.Data.ChapterRepo,
     YtSearch.Data.ChapterRepo.Replica1,
     YtSearch.Data.ChapterRepo.Replica2,
     YtSearch.Data.ChapterRepo.Replica3,
     YtSearch.Data.ChapterRepo.Replica4,
     YtSearch.Data.ChapterRepo.Replica5,
     YtSearch.Data.ChapterRepo.JanitorReplica
   ], "chapters"},
  {
    [
      YtSearch.Data.SponsorblockRepo,
      YtSearch.Data.SponsorblockRepo.Replica1,
      YtSearch.Data.SponsorblockRepo.Replica2,
      YtSearch.Data.SponsorblockRepo.Replica3,
      YtSearch.Data.SponsorblockRepo.Replica4,
      YtSearch.Data.SponsorblockRepo.Replica5,
      YtSearch.Data.SponsorblockRepo.JanitorReplica
    ],
    "sponsorblock"
  },
  {
    [
      YtSearch.Data.SubtitleRepo,
      YtSearch.Data.SubtitleRepo.Replica1,
      YtSearch.Data.SubtitleRepo.Replica2,
      YtSearch.Data.SubtitleRepo.Replica3,
      YtSearch.Data.SubtitleRepo.Replica4,
      YtSearch.Data.SubtitleRepo.Replica5,
      YtSearch.Data.SubtitleRepo.JanitorReplica
    ],
    "subtitles"
  },
  {
    [
      YtSearch.Data.LinkRepo,
      YtSearch.Data.LinkRepo.Replica1,
      YtSearch.Data.LinkRepo.Replica2,
      YtSearch.Data.LinkRepo.Replica3,
      YtSearch.Data.LinkRepo.Replica4,
      YtSearch.Data.LinkRepo.Replica5,
      YtSearch.Data.LinkRepo.JanitorReplica
    ],
    "links"
  },
  {
    [
      YtSearch.Data.AudioConfigRepo,
      YtSearch.Data.AudioConfigRepo.Replica1,
      YtSearch.Data.AudioConfigRepo.Replica2,
      YtSearch.Data.AudioConfigRepo.Replica3,
      YtSearch.Data.AudioConfigRepo.Replica4,
      YtSearch.Data.AudioConfigRepo.Replica5,
      YtSearch.Data.AudioConfigRepo.JanitorReplica
    ],
    "audio_configs"
  },
  {
    [
      YtSearch.Data.CounterRepo,
      YtSearch.Data.CounterRepo.Replica1,
      YtSearch.Data.CounterRepo.Replica2,
      YtSearch.Data.CounterRepo.Replica3,
      YtSearch.Data.CounterRepo.Replica4
    ],
    "counter"
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

config :yt_search, YtSearch.Constants,
  results_from_search: 19,
  results_from_channels: 19,
  results_from_playlists: 19,
  results_from_trending: 32,
  minimum_time_between_refreshes: 60,
  enable_periodic_tasks: true,
  enable_periodic_janitors: true,
  redirect_to_googlevideo?: true

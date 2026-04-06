import Config

# Configure your database

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
  },
] ++
  if(System.get_env("EXTERNAL_TRENDING_NODE") in [nil, ""],
    do: [
      {
        [
          YtSearch.Data.TrendingRepo,
          YtSearch.Data.TrendingRepo.Replica1,
          YtSearch.Data.TrendingRepo.Replica2
        ],
        "trending"
      }
    ],
    else: []
  )
|> Enum.each(fn {repos, name} ->
  for repo <- repos do
    config :yt_search, repo,
      database: Path.expand("../db/yt_search_dev_#{name}.db", Path.dirname(__ENV__.file)),
      pool_size: 1,
      stacktrace: true,
      show_sensitive_data_on_connection_error: true
  end
end)

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

import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/yt_search start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :yt_search, YtSearchWeb.Endpoint, server: true
end

if config_env() in [:dev, :prod] do
  config :yt_search, YtSearch.Youtube,
    piped_url: System.get_env("PIPED_URL") || "localhost:8080",
    sponsorblock_url: System.get_env("SPONSORBLOCK_URL") || "localhost:8081"
end

config :yt_search, YtSearch.ThumbnailAtlas,
  montage_command: System.get_env("MONTAGE_COMMAND") || "montage"

if config_env() in [:prod, :dev] do
  config :yt_search, YtSearch.Ratelimit,
    ytdlp_search: {
      (System.get_env("SEARCH_RATELIMIT_REQUESTS") || "2")
      |> Integer.parse()
      |> Tuple.to_list()
      |> Enum.at(0),
      (System.get_env("SEARCH_RATELIMIT_PER_MILLISECOND") || "4000")
      |> Integer.parse()
      |> Tuple.to_list()
      |> Enum.at(0)
    }
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search.db
      """

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
      database: database_path,
      pool_size: String.to_integer(System.get_env("POOL_SIZE") || "1")
  end

  slots_database_path =
    System.get_env("SLOTS_DATABASE_PATH") ||
      raise """
      environment variable SLOTS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_slots.db
      """

  for repo <- [
        YtSearch.Data.SlotRepo,
        YtSearch.Data.SlotRepo.Replica1,
        YtSearch.Data.SlotRepo.Replica2
      ] do
    config :yt_search, repo, database: slots_database_path
  end

  channel_slots_database_path =
    System.get_env("CHANNEL_SLOTS_DATABASE_PATH") ||
      raise """
      environment variable CHANNEL_SLOTS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_channel_slots.db
      """

  for repo <- [
        YtSearch.Data.ChannelSlotRepo,
        YtSearch.Data.ChannelSlotRepo.Replica1,
        YtSearch.Data.ChannelSlotRepo.Replica2
      ] do
    config :yt_search, repo, database: channel_slots_database_path
  end

  playlist_slots_database_path =
    System.get_env("PLAYLIST_SLOTS_DATABASE_PATH") ||
      raise """
      environment variable PLAYLIST_SLOTS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_playlist_slots.db
      """

  for repo <- [
        YtSearch.Data.PlaylistSlotRepo,
        YtSearch.Data.PlaylistSlotRepo.Replica1,
        YtSearch.Data.PlaylistSlotRepo.Replica2
      ] do
    config :yt_search, repo, database: playlist_slots_database_path
  end

  search_slots_database_path =
    System.get_env("SEARCH_SLOTS_DATABASE_PATH") ||
      raise """
      environment variable SEARCH_SLOTS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_search_slots.db
      """

  for repo <- [
        YtSearch.Data.SearchSlotRepo,
        YtSearch.Data.SearchSlotRepo.Replica1,
        YtSearch.Data.SearchSlotRepo.Replica2
      ] do
    config :yt_search, repo, database: search_slots_database_path
  end

  thumbnails_database_path =
    System.get_env("THUMBNAILS_DATABASE_PATH") ||
      raise """
      environment variable THUMBNAILS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_thumbnails.db
      """

  for repo <- [
        YtSearch.Data.ThumbnailRepo,
        YtSearch.Data.ThumbnailRepo.Replica1,
        YtSearch.Data.ThumbnailRepo.Replica2,
        YtSearch.Data.ThumbnailRepo.JanitorReplica
      ] do
    config :yt_search, repo, database: thumbnails_database_path
  end

  chapters_database_path =
    System.get_env("CHAPTERS_DATABASE_PATH") ||
      raise """
      environment variable CHAPTERS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_chapters.db
      """

  for repo <- [
        YtSearch.Data.ChapterRepo,
        YtSearch.Data.ChapterRepo.Replica1,
        YtSearch.Data.ChapterRepo.Replica2,
        YtSearch.Data.ChapterRepo.JanitorReplica
      ] do
    config :yt_search, repo, database: chapters_database_path
  end

  sponsorblock_database_path =
    System.get_env("SPONSORBLOCK_DATABASE_PATH") ||
      raise """
      environment variable SPONSORBLOCK_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_sponsorblock.db
      """

  for repo <- [
        YtSearch.Data.SponsorblockRepo,
        YtSearch.Data.SponsorblockRepo.Replica1,
        YtSearch.Data.SponsorblockRepo.Replica2,
        YtSearch.Data.SponsorblockRepo.JanitorReplica
      ] do
    config :yt_search, repo, database: sponsorblock_database_path
  end

  subtitles_database_path =
    System.get_env("SUBTITLES_DATABASE_PATH") ||
      raise """
      environment variable SUBTITLES_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_subtitles.db
      """

  for repo <- [
        YtSearch.Data.SubtitleRepo,
        YtSearch.Data.SubtitleRepo.Replica1,
        YtSearch.Data.SubtitleRepo.Replica2,
        YtSearch.Data.SubtitleRepo.JanitorReplica
      ] do
    config :yt_search, repo, database: subtitles_database_path
  end

  links_database_path =
    System.get_env("LINKS_DATABASE_PATH") ||
      raise """
      environment variable LINKS_DATABASE_PATH is missing.
      For example: /etc/yt_search/yt_search_links.db
      """

  for repo <- [
        YtSearch.Data.LinkRepo,
        YtSearch.Data.LinkRepo.Replica1,
        YtSearch.Data.LinkRepo.Replica2,
        YtSearch.Data.LinkRepo.JanitorReplica
      ] do
    config :yt_search, repo, database: links_database_path
  end

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :yt_search, YtSearchWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :yt_search, YtSearchWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :yt_search, YtSearchWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :yt_search, YtSearch.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

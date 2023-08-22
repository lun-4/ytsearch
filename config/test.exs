import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :yt_search, YtSearch.Repo,
  database: Path.expand("../yt_search_test.db", Path.dirname(__ENV__.file)),
  pool_size: 1,
  queue_target: 10000,
  queue_timeout: 10000,
  pool: Ecto.Adapters.SQL.Sandbox

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

config :yt_search, YtSearch.Youtube, piped_url: "example.org"

config :yt_search, YtSearch.Ratelimit, ytdlp_search: {100, 100}

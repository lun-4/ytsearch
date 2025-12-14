Code.put_compiler_option(:warnings_as_errors, true)
{:ok, _} = Application.ensure_all_started(:ex_machina)

# Start CTA HTTP server for tests
{:ok, _pid} = YtSearch.Test.CTAServer.start_link()

ExUnit.start(exclude: [:slow, :slower])

for repo <-
      Application.fetch_env!(:yt_search, :ecto_repos) do
  Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
end

Code.put_compiler_option(:warnings_as_errors, true)
{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start(exclude: [:slow])
Ecto.Adapters.SQL.Sandbox.mode(YtSearch.Repo, :manual)

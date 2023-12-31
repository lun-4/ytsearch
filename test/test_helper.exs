Code.put_compiler_option(:warnings_as_errors, true)
{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start(exclude: [:slow, :slower])

for repo <- [
      YtSearch.Repo,
      YtSearch.Data.SlotRepo,
      YtSearch.Data.ChannelSlotRepo,
      YtSearch.Data.PlaylistSlotRepo
    ] do
  Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
end

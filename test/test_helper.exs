Code.put_compiler_option(:warnings_as_errors, true)
{:ok, _} = Application.ensure_all_started(:ex_machina)
ExUnit.start(exclude: [:slow, :slower])

for repo <- [
      YtSearch.Repo,
      YtSearch.Data.SlotRepo,
      YtSearch.Data.ChannelSlotRepo,
      YtSearch.Data.PlaylistSlotRepo,
      YtSearch.Data.SearchSlotRepo,
      YtSearch.Data.ThumbnailRepo
    ] do
  Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
end

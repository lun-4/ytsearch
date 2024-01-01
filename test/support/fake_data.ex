defmodule YtSearch.Test.Data do
  alias YtSearch.Factory

  def png do
    File.read!("test/support/hq720.webp")
  end

  def png_response do
    %Tesla.Env{status: 200, headers: [{"content-type", "image/webp"}], body: png()}
  end

  def insert_slot() do
    Factory.Slot.insert(:slot, [], on_conflict: :replace_all)
  end

  def default_global_mock(extra_fn \\ nil) do
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "https://i.ytimg.com" <> _} ->
        png_response()

      %{method: :get, url: "https://yt3.ggpht.com" <> _} ->
        png_response()

      %{method: :get, url: "https://yt3.googleusercontent.com/ytc" <> _} ->
        png_response()

      env ->
        unless extra_fn == nil do
          extra_fn.(env)
        end
    end)
  end
end

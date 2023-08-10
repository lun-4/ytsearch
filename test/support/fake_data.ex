defmodule YtSearch.Test.Data do
  def png do
    File.read!("test/support/hq720.webp")
  end

  def png_response do
    %Tesla.Env{status: 200, headers: [{"content-type", "image/webp"}], body: png()}
  end

  def default_global_mock do
    Tesla.Mock.mock_global(fn
      %{method: :get, url: "https://i.ytimg.com" <> _} ->
        png_response()

      %{method: :get, url: "https://yt3.ggpht.com" <> _} ->
        png_response()

      %{method: :get, url: "https://yt3.googleusercontent.com/ytc" <> _} ->
        png_response()
    end)
  end
end

defmodule YtSearchWeb.ErrorJSONTest do
  use YtSearchWeb.ConnCase, async: true

  test "renders 404" do
    assert YtSearchWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert YtSearchWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error", technical_detail: nil}}
  end
end

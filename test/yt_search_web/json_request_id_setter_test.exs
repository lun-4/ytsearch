defmodule YtSearchWeb.JSONRequestIDSetterTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias YtSearchWeb.Endpoint.JSONRequestIDSetter

  @request_id "F29mDOh0xB3EWQAABBGh"

  defp run(body, content_type) do
    conn(:get, "/")
    |> put_resp_header("x-request-id", @request_id)
    |> then(fn conn ->
      if content_type do
        put_resp_content_type(conn, content_type)
      else
        conn
      end
    end)
    |> JSONRequestIDSetter.call([])
    |> send_resp(200, body)
  end

  test "injects request id and time into json object bodies" do
    conn = run(~s({"foo":"bar","nested":{"a":[1,2]}}), "application/json")
    decoded = Jason.decode!(conn.resp_body)

    assert decoded["__x_request_id"] == @request_id
    assert is_float(decoded["__time"])
    assert decoded["foo"] == "bar"
    assert decoded["nested"] == %{"a" => [1, 2]}
  end

  test "injects into an empty json object" do
    conn = run("{}", "application/json")
    decoded = Jason.decode!(conn.resp_body)

    assert decoded["__x_request_id"] == @request_id
    assert is_float(decoded["__time"])
    assert map_size(decoded) == 2
  end

  test "injects into a whitespace-only object without a trailing comma" do
    conn = run("{  }", "application/json")
    decoded = Jason.decode!(conn.resp_body)

    assert decoded["__x_request_id"] == @request_id
    assert is_float(decoded["__time"])
    assert map_size(decoded) == 2
  end

  test "injects into a body with leading whitespace" do
    conn = run(~s(  {"foo":"bar"}), "application/json")
    decoded = Jason.decode!(conn.resp_body)

    assert decoded["__x_request_id"] == @request_id
    assert is_float(decoded["__time"])
    assert decoded["foo"] == "bar"
  end

  test "injects into a pretty-printed object body" do
    conn = run("{\n  \"foo\": \"bar\"\n}", "application/json")
    decoded = Jason.decode!(conn.resp_body)

    assert decoded["__x_request_id"] == @request_id
    assert is_float(decoded["__time"])
    assert decoded["foo"] == "bar"
  end

  test "leaves json array bodies untouched" do
    conn = run(~s([1,2,3]), "application/json")
    assert conn.resp_body == "[1,2,3]"
  end

  test "leaves non-json content types untouched" do
    conn = run(~s({"foo":"bar"}), "text/plain")
    assert conn.resp_body == ~s({"foo":"bar"})
  end
end

defmodule YtSearchWeb.ErrorJSON do
  require Logger

  # If you want to customize a particular status code,
  # you may add your own clauses, such as:
  #
  # def render("500.json", _assigns) do
  #   %{errors: %{detail: "Internal Server Error"}}
  # end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def render("500.json", assigns) do
    assigned_reason = assigns |> Map.get(:reason)

    more_detail =
      case assigned_reason do
        nil ->
          nil

        reason ->
          map = %{
            reason: inspect(reason),
            stack:
              assigns.stack
              |> Enum.map(fn {_module, _function, _arity, location} ->
                %{
                  # where: "#{inspect(module)}.#{inspect(function)}/#{arity}"
                  location: inspect(location)
                }
              end)
          }

          Logger.error("an error happened while handling the request: #{inspect(map)}")
          map
      end

    %{
      errors: %{
        detail: Phoenix.Controller.status_message_from_template("500.json"),
        technical_detail: more_detail
      }
    }
  end

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end

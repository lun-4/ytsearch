defmodule YtSearchWeb.SlotJSON do
  def render("slot.json", %{slot: nil}) do
    %{error: true, errors: %{detail: "slot not found"}}
  end
end

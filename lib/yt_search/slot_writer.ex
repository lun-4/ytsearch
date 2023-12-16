defmodule YtSearch.SlotWriter do
  alias Ecto.Changeset
  use GenServer
  alias YtSearch.Repo
  alias ExHashRing.Ring

  def start_link(id, opts \\ []) do
    GenServer.start_link(__MODULE__, id, opts)
  end

  def update(changeset) do
    {:ok, id} = Ring.find_node(YtSearch.SlotWriterRing, changeset.data.id)
    [{writer, :self}] = Registry.lookup(YtSearch.SlotWriters, id)
    GenServer.cast(writer, {:update, changeset})
    Changeset.apply_changes(changeset)
  end

  def init(id) do
    ExHashRing.Ring.add_node(YtSearch.SlotWriterRing, "writer_#{id}", 1)
    Process.send_after(self(), :flush_changesets, 10000)
    {:ok, %{slots: %{}}}
  end

  def handle_cast({:update, changeset}, state) do
    new_state = %{
      slots: state.slots |> Map.put(changeset.data.id, changeset)
    }

    {:noreply, new_state}
  end

  def handle_info(:flush_changesets, state) do
    new_state = %{slots: %{}}

    state.slots
    |> Enum.each(fn {_, changeset} ->
      # send changeset to repo
      changeset
      |> Repo.update!()
    end)

    {:noreply, new_state}
  end
end

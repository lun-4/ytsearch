defmodule YtSearch.SearchSlot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  # this number must be synced with the world build
  @urls 100_000

  schema "search_slots" do
    field(:slots_json, :string)
    timestamps()
  end

  @spec fetch_by_id(Integer.t()) :: SearchSlot.t()
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s
    Repo.one(query)
  end

  def video_slots(search_slot) do
    search_slot.slots_json
    |> Jason.decode!()
  end

  @spec from(String.t()) :: SearchSlot.t()
  def from(slots_json) do
    %__MODULE__{slots_json: slots_json, id: find_available_id()}
    |> Repo.insert!()
  end

  defp find_available_id() do
    query = from s in __MODULE__, select: max(s.id)

    max_id =
      case Repo.one(query) do
        nil -> 0
        v -> v
      end

    possible_available_id = max_id + 1

    if possible_available_id > @urls do
      # delete lowest id
      query = from s in __MODULE__, select: min(s.id)
      min_id = Repo.one!(query)
      delete_query = from s in __MODULE__, where: s.id == ^min_id
      Repo.delete!(delete_query)

      # min_id is now an available id 
      min_id
    else
      possible_available_id
    end
  end

  # slot system
  # 100 k
  # {...}
end

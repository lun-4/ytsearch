defmodule YtSearch.Slot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "slots" do
    field(:youtube_id, :string)
  end

  @spec from(Integer.t()) :: Slot.t()
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s
    Repo.one(query)
  end

  @spec from(String.t()) :: Slot.t()
  def from(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    case Repo.one(query) do
      nil ->
        %__MODULE__{youtube_id: youtube_id, id: find_available_id()}
        |> Repo.insert!()

      slot ->
        slot
    end
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

  # this number must be synced with the world build
  @urls 100_000

  # slot system
  # 100 k
  # {...}
end

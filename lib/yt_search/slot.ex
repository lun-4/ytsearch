defmodule YtSearch.Slot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.TTL

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "slots" do
    field(:youtube_id, :string)
    timestamps()
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
        {:ok, new_id} = find_available_id()

        %__MODULE__{youtube_id: youtube_id, id: new_id}
        |> Repo.insert!()

      slot ->
        slot
    end
  end

  @max_id_retries 20
  # 12 hours
  @ttl 12 * 60 * 60
  # this number must be synced with the world build
  @urls 100_000

  defp find_available_id() do
    find_available_id(0)
  end

  @spec find_available_id(Integer.t()) :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id(retries) do
    # generate id, check if 

    random_id = :rand.uniform(@urls)
    query = from s in __MODULE__, where: s.id == ^random_id, select: s

    case Repo.one(query) do
      nil ->
        {:ok, random_id}

      slot ->
        # already existing from id, check if it needs to be
        # refreshed
        if TTL.expired?(slot, @ttl) do
          Repo.delete!(slot)
          {:ok, random_id}
        else
          if retries > @max_id_retries do
            {:error, :no_available_id}
          else
            find_available_id(retries + 1)
          end
        end
    end
  end

  # slot system
  # 100 k
  # {...}
end

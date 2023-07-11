defmodule YtSearch.Slot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.SlotUtilities

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "slots" do
    field(:youtube_id, :string)
    timestamps()
  end

  @spec fetch_by_id(Integer.t()) :: Slot.t() | nil
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s
    Repo.one!(query)
  end

  @spec from(String.t()) :: Slot.t()
  def from(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s
    # TODO proper ttl checking on fetch/1 and from/1
    case Repo.all(query) do
      [slot | _rest] ->
        slot

      [] ->
        {:ok, new_id} = find_available_id()

        %__MODULE__{youtube_id: youtube_id, id: new_id}
        |> Repo.insert!()
    end
  end

  def max_id_retries, do: 20
  # 12 hours
  def ttl, do: 12 * 60 * 60
  # this number must be synced with the world build
  def urls, do: 100_000

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end
end

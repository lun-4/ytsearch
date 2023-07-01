defmodule YtSearch.SearchSlot do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Ecto, only: [assoc: 2]
  alias YtSearch.Repo
  alias YtSearch.SlotUtilities

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  # this number must be synced with the world build
  @urls 100_000
  @max_id_retries 20
  # 20 minutes
  @ttl 20 * 60

  schema "search_slots" do
    field(:slots_json, :string)
    timestamps()
  end

  @spec fetch_by_id(Integer.t()) :: SearchSlot.t() | nil
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s
    Repo.one!(query)
  end

  def video_slots(search_slot) do
    search_slot.slots_json
    |> Jason.decode!()
  end

  def from_playlist(playlist) do
    playlist
    |> Enum.map(fn r ->
      {numeric, _fractional} = Integer.parse(r.slot_id)
      numeric
    end)
    |> Jason.encode!()
    # conflicts with Ecto.Query
    |> __MODULE__.from()
  end

  @spec from(String.t()) :: SearchSlot.t()
  def from(slots_json) do
    {:ok, new_id} = find_available_id()

    %__MODULE__{slots_json: slots_json, id: new_id}
    |> Repo.insert!()
  end

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__, @urls, @ttl, @max_id_retries)
  end
end

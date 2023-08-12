defmodule YtSearch.PlaylistSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.SlotUtilities

  @type t :: %__MODULE__{}
  @primary_key {:id, :integer, autogenerate: false}

  # 20 times to retry
  def max_id_retries, do: 20
  # 12 hours
  def ttl, do: 12 * 60 * 60
  # this number must be synced with the world build
  def urls, do: 100_000

  schema "playlist_slots" do
    field(:youtube_id, :string)
    timestamps()
  end

  @spec fetch(Integer.t()) :: Slot.t() | nil
  def fetch(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    Repo.one(query)
    |> TTL.maybe?(__MODULE__)
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

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end

  def as_youtube_url(slot) do
    "https://www.youtube.com/playlist?list=#{slot.youtube_id}"
  end
end

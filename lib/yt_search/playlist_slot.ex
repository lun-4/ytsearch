defmodule YtSearch.PlaylistSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.SlotUtilities
  require Logger

  @type t :: %__MODULE__{}
  @primary_key {:id, :integer, autogenerate: false}

  # 1 times to retry
  def max_id_retries, do: 1
  # 12 hours
  def ttl, do: 12 * 60 * 60
  # this number must be synced with the world build
  def urls, do: 20_000

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

  @spec fetch_by_youtube_id(String.t()) :: t() | nil
  def fetch_by_youtube_id(youtube_id) do
    query = from s in __MODULE__, where: s.youtube_id == ^youtube_id, select: s

    Repo.all(query)
    |> Enum.filter(fn playlist_slot ->
      TTL.maybe?(playlist_slot, __MODULE__) != nil
    end)
    |> Enum.at(0)
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

  def refresh(playlist_slot_id) do
    query = from s in __MODULE__, where: s.id == ^playlist_slot_id, select: s
    playlist_slot = Repo.one(query)

    unless playlist_slot == nil do
      Logger.info("refreshing playlist id #{playlist_slot.id}")

      playlist_slot
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      )
      |> YtSearch.Repo.update!()
    end
  end
end

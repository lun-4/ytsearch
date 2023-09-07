defmodule YtSearch.SearchSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.TTL
  alias YtSearch.Slot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias YtSearch.SlotUtilities
  require Logger

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  # 20 times to retry
  def max_id_retries, do: 2
  # 20 minutes
  def ttl, do: 20 * 60
  # this number must be synced with the world build
  def urls, do: 10_000

  schema "search_slots" do
    field(:slots_json, :string)
    field(:query, :string)
    timestamps()
  end

  @spec fetch_by_id(Integer.t()) :: SearchSlot.t() | nil
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    Repo.one(query)
    |> TTL.maybe?(__MODULE__)
  end

  def refresh(search_slot_id) do
    query = from s in __MODULE__, where: s.id == ^search_slot_id, select: s
    search_slot = Repo.one(query)

    unless search_slot == nil do
      Logger.info("refreshed search id #{search_slot.id}")

      search_slot
      |> Ecto.Changeset.change(
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      )
      |> Repo.update!()
    end
  end

  defp internal_id_for(%ChannelSlot{youtube_id: channel_id}) do
    "ytchannel://#{channel_id}"
  end

  defp internal_id_for(%PlaylistSlot{youtube_id: playlist_id}) do
    "ytplaylist://#{playlist_id}"
  end

  defp internal_id_for(text) when is_bitstring(text) do
    "ytsearch://#{text}"
  end

  def fetch_by_query(query) do
    query = from s in __MODULE__, where: s.query == ^(query |> internal_id_for), select: s

    Repo.all(query)
    |> Enum.filter(fn search_slot ->
      TTL.maybe?(search_slot, __MODULE__) != nil
    end)
    |> Enum.at(0)
  end

  def get_slots(search_slot) do
    search_slot.slots_json
    |> Jason.decode!()
  end

  def fetched_slots_from_search(search_slot) do
    search_slot
    |> get_slots
    |> Enum.map(fn maybe_slot ->
      {slot_type, youtube_id} =
        case maybe_slot do
          # old version of the field
          data when is_list(data) ->
            {nil, nil}

          slot when is_map(slot) ->
            {slot["type"], slot["youtube_id"]}
        end

      # assumes all slot types are "strict ttl" as in,
      # fetches won't give nil values if the respective slots
      # are going to be obliterated any time now
      case slot_type do
        t when t in ["video", "short", "livestream"] ->
          Slot.fetch_by_youtube_id(youtube_id)

        "playlist" ->
          PlaylistSlot.fetch_by_youtube_id(youtube_id)

        "channel" ->
          ChannelSlot.fetch_by_youtube_id(youtube_id)

        nil ->
          nil

        _ ->
          raise "invalid type for search slot entry: #{inspect(slot_type)}"
      end
    end)
    |> Enum.filter(fn result -> result != nil end)
  end

  def from_playlist(playlist, search_query) do
    playlist
    |> Jason.encode!()
    |> from_slots_json(search_query |> internal_id_for)
  end

  @spec from_slots_json(String.t(), String.t()) :: SearchSlot.t()
  defp from_slots_json(slots_json, search_query) do
    {:ok, new_id} = find_available_id()

    %__MODULE__{slots_json: slots_json, id: new_id, query: search_query}
    |> Repo.insert!()
  end

  @spec find_available_id() :: {:ok, Integer.t()} | {:error, :no_available_id}
  defp find_available_id() do
    SlotUtilities.find_available_slot_id(__MODULE__)
  end
end

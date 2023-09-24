defmodule YtSearch.SearchSlot do
  use Ecto.Schema
  import Ecto.Query
  alias YtSearch.Repo
  alias YtSearch.Slot
  alias YtSearch.ChannelSlot
  alias YtSearch.PlaylistSlot
  alias YtSearch.SlotUtilities
  import Ecto.Changeset
  require Logger

  @type t :: %__MODULE__{}

  @primary_key {:id, :integer, autogenerate: false}

  schema "search_slots_v3" do
    field(:slots_json, :string)
    field(:query, :string)
    timestamps(autogenerate: {SlotUtilities, :generate_unix_timestamp, []})
    field(:expires_at, :naive_datetime)
    field(:used_at, :naive_datetime)
    field(:keepalive, :boolean)
  end

  def slot_spec() do
    %{
      max_ids: 10_000,
      ttl: 20 * 60
    }
  end

  @spec fetch_by_id(Integer.t()) :: SearchSlot.t() | nil
  def fetch_by_id(slot_id) do
    query = from s in __MODULE__, where: s.id == ^slot_id, select: s

    Repo.one(query)
    |> SlotUtilities.strict_ttl()
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

    Repo.one(query)
    |> SlotUtilities.strict_ttl()
  end

  def get_slots(search_slot) do
    search_slot.slots_json
    |> Jason.decode!()
  end

  def fetched_slots_from_search(search_slot) do
    search_slot
    |> get_slots
    |> Enum.map(fn %{"type" => slot_type, "youtube_id" => youtube_id} = maybe_slot ->
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
          Logger.warning("invalid type from #{inspect(maybe_slot)}")
          nil

        _ ->
          raise "invalid type for search slot entry: #{inspect(slot_type)}"
      end
    end)
  end

  def changeset(%__MODULE__{} = slot, params) do
    slot
    |> cast(params, [:id, :query, :slots_json, :expires_at, :used_at, :keepalive])
    |> validate_required([:query, :slots_json, :expires_at, :used_at])
  end

  def from_playlist(playlist, search_query, opts \\ []) do
    playlist
    |> Jason.encode!()
    |> from_slots_json(search_query |> internal_id_for, opts)
  end

  @spec from_slots_json(String.t(), String.t(), Keyword.t()) :: SearchSlot.t()
  defp from_slots_json(slots_json, search_query, opts) do
    keepalive = Keyword.get(opts, :keepalive, false)

    Repo.transaction(fn ->
      query = from s in __MODULE__, where: s.query == ^search_query, select: s
      search_slot = Repo.one(query)

      if search_slot == nil do
        {:ok, new_id} = SlotUtilities.generate_id_v3(__MODULE__)

        params =
          %{
            id: new_id,
            query: search_query,
            slots_json: slots_json,
            keepalive: keepalive
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_used()

        %__MODULE__{}
        |> changeset(params)
        |> Repo.insert!(
          on_conflict: [
            set: [
              query: params.query,
              slots_json: params.slots_json,
              expires_at: params.expires_at,
              used_at: params.used_at,
              keepalive: params.keepalive
            ]
          ]
        )
      else
        search_slot
        |> changeset(
          %{
            slots_json: slots_json,
            keepalive: keepalive
          }
          |> SlotUtilities.put_simple_expiration(__MODULE__)
          |> SlotUtilities.put_opts(opts)
          |> SlotUtilities.put_used()
        )
        |> Repo.update!()
      end
    end)
    |> then(fn {:ok, slot} -> slot end)
  end

  def urls, do: 0
end
